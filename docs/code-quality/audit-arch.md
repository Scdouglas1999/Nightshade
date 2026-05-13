# Nightshade Architecture & File-Structure Audit

| Audit ID | Branch | Base commit | Date |
|----------|--------|-------------|------|
| CQ-AUDIT-ARCH | `worktree-agent-a8057c6aa84047f39` (off `main`) | `bbdee9b` ("fixed a ton of bugs") | 2026-05-12 |

> Scope: read-only structural review. No code changed. The branch is ~50 commits beyond the orchestrator-referenced commit `0c88691` (SIMBAD), so findings reflect the current `main` tip, not the pre-W7 hardening branch.

---

## 1. Monolithic files

### 1.1 Top 25 largest source files (Dart + Rust)

| # | LOC | Path | Generated? |
|---|----:|------|-----------|
| 1 | 28,879 | `packages/nightshade_core/lib/src/database/database.g.dart` | drift |
| 2 | 26,894 | `packages/nightshade_bridge/lib/src/event.freezed.dart` | freezed |
| 3 | 25,137 | `native/nightshade_native/bridge/src/frb_generated.rs` | frb |
| 4 | 16,665 | `packages/nightshade_bridge/lib/src/frb_generated.dart` | frb |
| 5 | 14,965 | `packages/nightshade_bridge/lib/src/error.freezed.dart` | freezed |
| 6 | 14,601 | `packages/nightshade_bridge/lib/src/frb_generated.io.dart` | frb |
| 7 | 9,770 | `native/nightshade_native/bridge/src/api.rs` | hand |
| 8 | 8,854 | `native/nightshade_native/bridge/src/devices.rs` | hand |
| 9 | 7,079 | `packages/nightshade_app/lib/screens/imaging/imaging_screen.dart` | hand |
| 10 | 5,847 | `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` | hand |
| 11 | 5,751 | `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` | hand |
| 12 | 4,871 | `packages/nightshade_app/lib/screens/sequencer/widgets/node_properties_panel.dart` | hand |
| 13 | 4,814 | `packages/nightshade_app/lib/screens/settings/settings_screen.dart` | hand |
| 14 | 4,688 | `packages/nightshade_app/lib/screens/framing/framing_screen.dart` | hand |
| 15 | 3,900 | `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` | hand |
| 16 | 3,756 | `native/nightshade_native/ascom/src/windows_impl.rs` | hand |
| 17 | 3,744 | `native/nightshade_native/sequencer/src/instructions.rs` | hand |
| 18 | 3,592 | `packages/nightshade_bridge/lib/src/api.dart` | hand wrapper |
| 19 | 3,533 | `packages/nightshade_core/lib/src/providers/sequence_provider.dart` | hand |
| 20 | 3,491 | `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart` | hand |
| 21 | 3,410 | `packages/nightshade_bridge/lib/src/bridge_stub.dart` | hand |
| 22 | 3,089 | `native/nightshade_native/bridge/src/real_device_ops.rs` | hand |
| 23 | 3,010 | `packages/nightshade_core/lib/src/backend/network_backend.dart` | hand |
| 24 | 2,992 | `packages/nightshade_webrtc/lib/src/web_server.dart` | hand |
| 25 | 2,981 | `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` | hand |

There are **38 source files >2,000 LOC**; 17 of those are generated.

### 1.2 Detailed split proposals (hand-written files)

#### `native/nightshade_native/bridge/src/api.rs` (9,770 LOC)
58 `pub fn api_*` FRB entry points + ~30 helpers, organized by `// =====` banner sections (verified at `api.rs:46-1658`). Split into `api/` submodules grouped by banner section: `init.rs`, `discovery.rs`, `connection.rs` (~1,400 LOC), `camera.rs` (~1,200 LOC), `mount.rs` (~900), `focuser.rs`, `filter_wheel.rs`, `dome.rs`, `switch.rs`, `cover_calibrator.rs`, `imaging.rs` (FITS/XISF/debayer/star detect), `plate_solving.rs`, `sequencer.rs`, `profiles.rs`, `misc.rs`. Effort **L**; recommend 3 PRs grouped by domain so FRB codegen runs are tractable.

#### `native/nightshade_native/bridge/src/devices.rs` (8,854 LOC)
One `impl DeviceManager` with 116 methods. Major segments: `HeartbeatConfig`/`ReconnectConfig` setup (lines 68–470), connection lifecycle (`register_device`, `connect_device`, `disconnect_device` — lines 686–1569; `connect_device` alone is ~880 LOC), querying + API-version negotiation (lines 1570–1990), per-device-type dispatch (lines 1990–8854). Split into `bridge/src/device_manager/{mod.rs, connection.rs, heartbeat.rs, api_version.rs, ops/{camera,mount,focuser,filter_wheel,dome,rotator,weather,safety,switch,cover}.rs}`. Effort **L** — every move touches `Arc<RwLock<...>>` field access; expect borrow-checker churn.

#### Remaining hand-written files >2k LOC

| File | LOC | Sketch of decomposition | Effort |
|---|---:|---|---|
| `screens/imaging/imaging_screen.dart` | 7,079 | `_ImagingScreenState`, `_LivePreviewArea` stay; extract `widgets/imaging_overlays.dart`, `widgets/imaging_panel_tabs.dart`, `widgets/image_display.dart`, `painters/overlay_painters.dart`, `painters/science_painters.dart` (4 science painters, line 2910–3290), `widgets/histogram.dart` | M |
| `screens/dashboard/dashboard_screen.dart` | 5,751 | Extract `widgets/command_bar.dart`, `widgets/dashboard_tiles.dart`, `widgets/clock_widget.dart`, `widgets/dashboard_actions.dart`, `widgets/widget_picker_dialog.dart`, `widgets/live_preview_card.dart` (latter duplicates concepts in imaging_screen — share) | M |
| `screens/planetarium/planetarium_screen.dart` | 5,847 | Extract `widgets/planetarium_overlays.dart`, `widgets/planetarium_controls.dart`, `tabs/tonight_tab.dart`, `tabs/objects_tab.dart`, `tabs/search_results_tab.dart`, `tabs/info_tab.dart` | M |
| `screens/sequencer/widgets/node_properties_panel.dart` | 4,871 | Move per-node-type classes (`_ExposureProperties`, `_LoopProperties`, `_CenterProperties`, etc.) each into `widgets/node_properties/properties/<type>.dart`; common inputs into `widgets/node_properties/inputs/` | M |
| `screens/settings/settings_screen.dart` | 4,814 | Already organized by `_*Settings` section class. 1:1 extraction into `screens/settings/sections/` | M |
| `screens/framing/framing_screen.dart` | 4,688 | Extract `widgets/framing_canvas.dart`, `widgets/canvas_controls.dart`, `painters/fov_painters.dart` (lines 2081–2685), `painters/background_painters.dart`, `widgets/info_overlays.dart` | M |
| `screens/sequencer/tabs/templates_tab.dart` | 3,900 | Extract `widgets/template_card.dart` (`_TemplateCard*`), `widgets/save_template_dialog.dart`, `widgets/templates_header.dart` | M |
| `native/.../ascom/src/windows_impl.rs` | 3,756 | 35 structs already per-device; carve into `windows/connection.rs`, `windows/camera.rs`, `windows/mount.rs`, `windows/focuser.rs`, `windows/filter_wheel.rs`, `windows/rotator.rs`, `windows/dome.rs`, `windows/safety_monitor.rs`, `windows/observing_conditions.rs`, `windows/switch.rs`, `windows/cover_calibrator.rs`. Low risk — almost no shared mutable state | M |
| `native/.../sequencer/src/instructions.rs` | 3,744 | Unclear without deeper read — only two `impl` blocks at top level. Likely instruction-type enum match arms dominate. | M |
| `providers/sequence_provider.dart` | 3,533 | Extract `sequence_executor.dart` (`SequenceExecutor`, line 1547–2951 = 1,400 LOC), `sequence_validation.dart`, `sequencer_defaults.dart`, `node_palette.dart` | M |
| `planetarium/lib/src/rendering/sky_renderer.dart` | 3,491 | Extract `painters/sky_canvas_painter.dart` (line 510+), `cache/paint_cache.dart`, `cache/text_cache.dart`, `cache/shader_cache.dart` | M |
| `bridge/lib/src/api.dart` | 3,592 | Hand-written wrapper around frb_generated; structurally tied to api.rs split (§ api.rs row). | M |
| `bridge/lib/src/bridge_stub.dart` | 3,410 | Hide-list re-exporter; consider keeping as-is. | S |
| `native/.../bridge/src/real_device_ops.rs` | 3,089 | One `RealDeviceOps` impl + `AlpacaConnectionInfo`. Could split into per-device-type modules mirroring `devices.rs`. | M |
| `core/lib/src/backend/network_backend.dart` | 3,010 | One class implementing the full `NightshadeBackend` interface (~150 methods). **Defer** — split the interface first (§7). | L (deferred) |
| `webrtc/lib/src/web_server.dart` | 2,992 | Single `NightshadeWebServer` class. Likely route-based split possible. Unclear without deeper read. | M |
| `screens/polar_alignment/polar_alignment_screen.dart` | 2,981 | ~15 painter/widget classes. Extract `painters/error_trend.dart`, `painters/bullseye.dart`, `widgets/instruction_step.dart` | M |
| `native/.../indi/src/client.rs` | 2,756 | Single `IndiClient` impl 286–2000. Split into `client/connection.rs`, `client/properties.rs`, `client/switches.rs`, `client/numbers.rs`, `client/blobs.rs` | M |
| `screens/equipment/tabs/connections_tab.dart` | 2,723 | Five `_*DeviceCard` (camera/mount/focuser/filter wheel/guider). One file each. | **S** |
| `core/lib/src/services/device_service.dart` | 2,696 | One `DeviceService` class. Split per device type. | M |
| `core/lib/src/backend/ffi_backend.dart` | 2,577 | One `FfiBackend implements NightshadeBackend`. Same deferral as network_backend. | L (deferred) |
| `native/.../native/src/vendor/zwo.rs` (2,572), `fujifilm.rs` (2,556), `qhy.rs` (1,883), `touptek.rs` (1,316), `svbony.rs` (1,279), `atik.rs` (1,252), `player_one.rs` (1,218) | — | Vendor SDK FFI binding bodies. Splitting offers little value. **Leave alone.** | (no action) |
| `core/lib/src/models/sequence/sequence_models.dart` | 2,452 | Many model classes (`Sequence`, plus per-node classes). Split into `sequence_models/instructions.dart`, `sequence_models/triggers.dart`, `sequence_models/logic_nodes.dart`. | M |
| `native/.../sequencer/src/node.rs` | 2,369 | Sequencer behavior tree node enums. Unclear without deeper read. | M |
| `core/lib/src/models/tutorial/tutorial_models.dart` | 2,004 | Tutorial-step data. Unclear if splitting helps. | S |
| `screens/imaging/tabs/focus_tab.dart` (2,035), `screens/equipment/dialogs/profile_editor_dialog.dart` (2,012), `screens/settings/equipment_profiles_screen.dart` (2,296) | — | Each 1 screen, ~10 sub-widgets. Mechanical extraction. | S–M each |

---

## 2. Name collisions resolved via `hide` / `show`

### 2.1 Verified hide clauses in non-test code

| # | File:Line | Hide clause | Status |
|---|---|---|---|
| 1 | `packages/nightshade_core/lib/nightshade_core.dart:6` | `database` `hide Target, Sequence, SequenceNode, CapturedImage, EquipmentProfile` | live |
| 2 | `packages/nightshade_core/lib/nightshade_core.dart:29` | `models/settings/app_settings.dart hide AppSettings` | live |
| 3 | `packages/nightshade_core/lib/nightshade_core.dart:58` | `providers/framing_provider.dart hide MosaicConfig, MosaicPanel` | live |
| 4 | `packages/nightshade_core/lib/nightshade_core.dart:89` | `backend/nightshade_backend.dart hide CameraState` | live |
| 5 | `packages/nightshade_core/lib/nightshade_core.dart:100` | `services/plate_solve_service.dart hide PlateSolveResult` | live |
| 6 | `packages/nightshade_core/lib/nightshade_core.dart:109` | `services/focus_model_service.dart hide FocusDataPoint` | live |
| 7 | `packages/nightshade_bridge/lib/nightshade_bridge.dart:7-30` | `bridge_stub.dart hide` (19 types incl. `AutofocusConfigApi`, `AutofocusResultApi`, `CapturedImageResult`, `CheckpointInfoApi`, `ImageStatsResult`, `Phd2Status`, `Phd2StarImage`, `PlateSolveResult`, `SequencerState`, `NightshadeEvent`, `EventSeverity`, `EventCategory`, `PolarAlignmentEvent`, `DeviceType`, `DriverType`, `CameraState`, `CameraStatus`, `DeviceInfo`, `FilterWheelStatus`, `FocuserStatus`, `MountStatus`, `PierSide`, `RotatorStatus`, `TrackingRate`, `FrameType`, `ShutterState`) | live — largest hide surface |
| 8 | `packages/nightshade_core/lib/src/services/device_service.dart:18` | `../backend/nightshade_backend.dart hide TrackingRate` | live |
| 9 | `packages/nightshade_core/lib/src/services/backup_service.dart:8` | `../database/database.dart hide Sequence, SequenceNode` | live |
| 10 | `packages/nightshade_core/lib/src/backend/disconnected_backend.dart:8` | `../providers/settings_provider.dart hide AppSettings` | live |
| 11 | `packages/nightshade_core/lib/src/backend/ffi_backend.dart:16` | `database hide EquipmentProfile, CapturedImage` | live |
| 12 | `packages/nightshade_core/lib/src/providers/guiding_provider.dart:6` | `nightshade_bridge hide EventCategory, Phd2GuideStats, Phd2StarImage, Phd2CalibrationData` | live |
| 13 | `packages/nightshade_bridge/lib/src/event.dart:9`, `error.dart:8`, `device_capabilities.dart:9` | `freezed_annotation hide protected` (3 files) | freezed/Flutter material `protected` shadow — benign |
| 14 | `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart:9` | `nightshade_planetarium hide sessionProgressProvider` | live |
| 15 | `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart:7` and `widgets/science_analytics_tab.dart:7` | `nightshade_core hide CapturedImage` | live (2 sites) |
| 16 | `packages/nightshade_app/lib/screens/equipment/widgets/mount_control_panel.dart:4` | `nightshade_core hide DeviceType` | live |
| 17 | `packages/nightshade_app/lib/services/location_sync_service.dart:5` | `nightshade_planetarium hide ObserverLocation` | live |
| 18 | `packages/nightshade_app/lib/screens/framing/framing_screen.dart:13` | `nightshade_core hide TargetSearchState, targetSearchProvider` | live |
| 19 | `packages/nightshade_app/lib/screens/guiding/guiding_screen.dart:5` and `imaging/tabs/guiding_tab.dart:5` | `nightshade_core hide Phd2GuidingState, GuideErrorPoint` | live (2 sites) |
| 20 | `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart:3` | `drift hide Column` | benign (third-party clash) |
| 21 | `apps/mobile/lib/services/mobile_sequence_hooks.dart:3` | `nightshade_core hide NotificationService` | live |

### 2.2 Collision triage

| Collision | Sites | Kind | Recommendation | Effort |
|---|---|---|---|---|
| `MosaicConfig` / `MosaicPanel` | `services/mosaic_service.dart:9,30`, `providers/framing_provider.dart:343,408`, `planetarium/services/mosaic_planner.dart:43,147` | 3-way drift | Keep `services/mosaic_service.dart`. Rename framing→`Framing*`. Delete planetarium. | M |
| `FocusDataPoint` | `services/focus_model_service.dart:16`, `models/backend/autofocus_result.dart:6` (canonical), `bridge/api.dart:2443` (FRB) | Accidental drift | Delete service-local; migrate to canonical. | S |
| `PlateSolveResult` | `services/plate_solve_service.dart:10`, `models/backend/plate_solve_result.dart:4` (canonical), `bridge/api.dart:2916` (FRB) | Accidental drift | Delete service-local. | S |
| `AppSettings` | `providers/settings_provider.dart:10`, `models/settings/app_settings.dart:29` (canonical freezed), `database/tables/settings.dart:6` (drift), `bridge/storage.dart:9` (FRB) | Domain split | Rename `providers/settings_provider.dart` class to `AppSettingsState`. | S |
| `CameraState` | `models/equipment/equipment_models.dart:225` (class), `bridge/device.dart:32` (enum), `models/backend/device_types.dart:43` (enum) | Status class vs lifecycle enum | Rename equipment_models class → `CameraStateSnapshot`. Consolidate the two enums. | M |
| `DeviceType` | `bridge/device.dart:317`, `models/backend/device_types.dart:4`, `equipment/widgets/device_card.dart:5` | 3 duplicate enums | Delete device_card local. Bridge↔core split is FRB-forced. | S |
| `ObserverLocation` | `bridge/storage.dart:40`, `planetarium/providers/planetarium_providers.dart:60`, `models/settings/app_settings.dart:17` (canonical) | 3 duplicates | Rename planetarium → `PlanetariumObserver`. | S |
| `EventCategory`, `TrackingRate` | bridge enum vs core enum mirrors | FRB-forced mirror | (no action) |
| `Phd2GuidingState` | `models/phd2_models.dart:8` (canonical), `ui/widgets/phd2/guide_controls_panel.dart:6` (dup enum) | UI-local duplicate | Delete UI-local; import canonical. Removes 2 `hide` clauses. | S |
| `GuideErrorPoint` | `models/phd2_models.dart:133` (freezed), `ui/widgets/phd2/guide_target_display.dart:6` (plain class) | UI-local duplicate | Same. | S |
| `TargetSearchState` / `targetSearchProvider` | `providers/framing_provider.dart:1485` (canonical), `nightshade_app/.../framing_search_provider.dart:7`, `apps/desktop/.../framing_search_provider.dart:6` and `apps/desktop/.../targets_tab.dart:12` | Provider + app shim + sequencer-local string provider that happens to share the name | Rename desktop targets_tab one → `sequenceTargetSearchProvider`. Remove app-shim. | S–M |
| `NotificationService` | `services/notification_service.dart:30` (core), `apps/mobile/.../notification_service.dart:5` | Platform split | Rename mobile → `MobileNotificationService`. | S |
| `sessionProgressProvider` | `providers/session_provider.dart:389`, `planetarium/providers/target_queue_provider.dart:544` | Drift; dashboard hides planetarium one | Rename planetarium → `queueProgressProvider`. | S |
| `HorizonProfile`, `FirstNightWizard`, `AnnotationPreset`, scheduler `TwilightTimes` | not found in current tree | resolved | (no action) |

---

## 3. Cross-package dependency cycles + layer violations

### 3.1 Core ↦ App imports
Zero. `git grep "package:nightshade_app"` against `packages/nightshade_core` and `packages/nightshade_bridge` returns nothing. Layering at that boundary is clean.

### 3.2 `src/` bypass imports (leaky abstraction)

| Group | Files | Severity | Notes |
|---|---|---|---|
| App → `nightshade_core/src/database/database.dart` for drift `CapturedImage`/`EquipmentProfile` | `screens/equipment/widgets/{quick_connect_bar.dart:4, profile_chip.dart:4, connection_status_zone.dart:5}`, `screens/equipment/tabs/{profiles_tab.dart:7, connections_tab.dart:7}`, `screens/analytics/{analytics_screen.dart:8, widgets/session_chart.dart:5, widgets/science_analytics_tab.dart:9, widgets/image_thumbnail_strip.dart:6}` | medium | Workaround for the barrel `hide` on those names |
| App → `nightshade_core/src/providers/framing_provider.dart` to access hidden `MosaicConfig`/`MosaicPanel` | `screens/framing/framing_screen.dart:14` | medium | Same pattern |
| **UI → `nightshade_bridge/src/api.dart` & `event.dart`** | `nightshade_ui/lib/src/widgets/polar_alignment_wizard.dart:6,7` | **high** | UI package couples directly to FRB internals — worst violation found |
| Core backend → `nightshade_bridge/src/*` | `core/lib/src/backend/ffi_backend.dart:11–14` (api, device_capabilities, device, error) | low | Intentional bridge wiring but should use the public barrel |
| Self-package full `package:` URLs instead of relative imports | `core/lib/src/backend/{ffi_backend.dart:8,15,17, network_backend.dart:9}`, `core/lib/src/models/meridian_flip_event.dart:2` | style only | |

App's `database.dart` bypass is the design's own contradiction: app code needs the drift entity, but the barrel hides it. Fix: either re-export with an alias (`export ... show EquipmentProfile as DbEquipmentProfile`) or stop hiding and rename the model-class version (the `CameraStateSnapshot` strategy from §2.2).

`apps/desktop/lib/` and `apps/mobile/lib/` cleanly use public barrels — no `src/` bypass except `apps/desktop/.../targets_tab.dart:3 hide Column` (drift third-party clash).

### 3.3 Test-code `src/` imports
~12 test files reach into `src/`. Legitimate.

---

## 4. Deprecated members still in use

| Symbol | Defined | Callers in non-test code | Action |
|---|---|---|---|
| `NightshadeDeviceType` (typedef) | `services/device_service.dart:80` | None found outside the type alias itself | **Delete now**, no migration needed. |
| `DriverBackend` (typedef = `DriverType`) | `services/device_service.dart:83` | Used (94 occurrences in 7 files): `equipment/discovery_state.dart`, `equipment/unified_device.dart`, `services/device_service.dart`, `services/device_matching_service.dart`, `providers/unified_discovery_provider.dart`, `providers/device_backend_selection_provider.dart` | Bulk rename `DriverBackend` → `DriverType` in those six files, then delete typedef. **M** effort. |
| `AvailableDevice` (typedef = `DeviceInfo`) | `services/device_service.dart:86` | Used (21 occurrences in 5 files, same set as DriverBackend) | Bulk rename `AvailableDevice` → `DeviceInfo`, then delete typedef. **S**. |
| `DeviceInfo.backend` (getter) | `models/backend/device_info.dart:23` | No callers (grep `device.backend\|deviceInfo.backend\|info.backend` returns 0 in dart files) | Delete now. |
| `DeviceInfo.type` (getter) | `models/backend/device_info.dart:27` | Likely some callers — `.type` is too generic to grep cleanly. Verify before delete. | Manually trace, then delete. |
| `TargetGroupNode` (typedef = `TargetHeaderNode`) | `models/sequence/sequence_models.dart:379` | 21 occurrences across 10 files including bridge generated, services (`scheduler_service.dart`, `mosaic_service.dart`, `backup_service.dart`, `sequence_models.dart`), and `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` | Bulk rename `TargetGroupNode` → `TargetHeaderNode`, delete typedef. **S** (FRB regen needed). |
| `Sequence.targetHeaders` (deprecation message says "Use targetHeaders instead") | `sequence_models.dart:2284` | Internal — review the field itself, may already be fixed. | Spot-check. |
| `PluginApi.onLoad(legacy)`, `onUnload(legacy)` | `plugin_api.dart:55,59` | Plugin API public surface | Keep at least one major version then remove. |

---

## 5. Generated-code-in-repo policy

### 5.1 Footprint
- **64 committed generated files**, **153,706 LOC total**.
- 4 generated files are >10,000 LOC each (drift `database.g.dart`, freezed `event.freezed.dart`, `error.freezed.dart`, and FRB `frb_generated.rs`).
- Generated files are **47.5% of all `.dart`/`.rs`/`.js`/`.ts` LOC in the repo** (153,706 of 323,235 + 19,103 ≈ 0.45).
- `.gitignore` shows generated files are intentionally committed (the only `*.g.dart`/`*.freezed.dart` rule is `*.g.dart.info` markers).
- Regeneration command exists: `melos run generate` → `melos exec -- dart run build_runner build --delete-conflicting-outputs` (`melos.yaml`). FRB regen is `flutter_rust_bridge_codegen generate` (documented with platform CPATH gymnastics in `CLAUDE.md` and `docs/FRB_TROUBLESHOOTING.md`).

### 5.2 Trade-offs
**Pros of committing:** green builds without LLVM/CPATH setup; `dart analyze` runs without codegen step; FRB Windows-codegen friction makes uncommitted bindings risky for non-Windows + CI.
**Cons:** ~47% of all source LOC is machine output → noisy diffs, slow `git log`/`git grep`; FRB-API change produces 50k+ LOC diff (event/error/frb_generated trio); `database.g.dart` (28,879 LOC) churns on every schema change.

### 5.3 Recommendation
**Keep committed.** FRB-codegen friction outweighs diff-noise cost. Mitigations:
1. `.gitattributes linguist-generated=true` for `*.g.dart`, `*.freezed.dart`, `frb_generated*` → GitHub collapses in PR diffs.
2. CI job runs `melos run generate` and fails if output differs from committed → guarantees in-sync.
3. CODEOWNERS rule so generated files don't trigger reviewer assignment.

---

## 6. Riverpod provider sprawl

- **35 provider files** in `packages/nightshade_core/lib/src/providers/`.
- **248 top-level `final ... Provider = ...` declarations** across 32 of those files (the other 3 only host StateNotifier classes).

### Top 10 largest provider files

| LOC | File | Provider count |
|---:|---|---:|
| 3,533 | `sequence_provider.dart` | 8 |
| 1,753 | `framing_provider.dart` | 3 |
| 1,540 | `equipment_provider.dart` | 13 |
| 1,183 | `settings_provider.dart` | 6 |
| 877 | `guiding_provider.dart` | 13 |
| 780 | `auto_stretch_provider.dart` | 4 |
| 737 | `science_provider.dart` | 34 |
| 663 | `profiles_provider.dart` | 6 |
| 657 | `transient_alert_provider.dart` | 7 |
| 559 | `polar_alignment_provider.dart` | 7 |

### Files that should be split
- `science_provider.dart` (34 providers / 737 LOC) — split per science feature (session, photometry, transparency, …). Effort **S–M**.
- `imaging_provider.dart` (32 providers) — split capture/preview/stretch state. Effort **M**.
- `guiding_provider.dart` (13 providers / 877 LOC) — split `guide_stats_provider.dart`, `guide_graph_provider.dart`, `guide_calibration_provider.dart`. Effort **M**.
- `equipment_provider.dart` (13 providers / 1,540 LOC) — `CameraStateNotifier` lives here despite type living in models; carve per-device-type providers.
- `sequence_provider.dart` — see §1.2.

### Provider-type consistency
Healthy mix. `StateNotifierProvider` for mutating state, `Provider`/`StreamProvider` for derived. ~134 stateful providers, ~114 derived `Provider<T>` — no widespread misuse seen.

---

## 7. Module-boundary recommendations

| Restructure | Effort | Recommend? | Rationale |
|---|---|---|---|
| Split `nightshade_core` → `nightshade_data` (drift + DAOs + DB models) + `nightshade_domain` (services + providers + freezed models) | L | **Yes** | Resolves the 5-name barrel `hide` + the §3.2 app-bypass tax structurally. Explicit `domain → data` arrow. |
| Carve `nightshade_bridge` → `_core` (FRB-generated) + `_dart` (hand-written wrappers in `api.dart`, `event.dart`, `device.dart`) | L | Conditional | Barrel currently hides 19+ types. Two packages would make the FRB ↔ wrapper boundary explicit. Worth it only if FRB regen becomes frequent. |
| Extract `nightshade_screens_*` packages from `nightshade_app` (imaging/planetarium/dashboard/settings) | L | **No** | `nightshade_app` is already a screen aggregator. Split the individual screen files (§1.2) first. |
| Stop re-exporting `nightshade_planetarium` providers through `nightshade_core` | M | Yes | `dashboard_screen.dart:9` hides `sessionProgressProvider` because both packages own session progress. |
| Move desktop-only `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` into `packages/nightshade_app` | S | Yes | Desktop has duplicated `framing_search_provider.dart`; desktop should carry only desktop-specific glue. |

---

## 8. Quick wins vs deep refactors

| # | Item | Type | Effort | Impact |
|---|---|---|---|---|
| 1 | Add `.gitattributes` `linguist-generated=true` for `*.freezed.dart`, `*.g.dart`, `frb_generated*` (collapses 153k LOC in PR diffs) | config | S | high |
| 2 | Delete `Phd2GuidingState` & `GuideErrorPoint` UI-local duplicates (`nightshade_ui/.../phd2/guide_controls_panel.dart:6`, `guide_target_display.dart:6`); removes 2 `hide` clauses | delete | S | high |
| 3 | Bulk-rename callers of `DriverBackend`/`AvailableDevice`/`NightshadeDeviceType`, then delete the 3 deprecated typedefs (115+ call sites) | rename | S–M | high |
| 4 | Delete `FocusDataPoint` / `PlateSolveResult` service-local duplicates, migrate to canonical `models/backend/*` (removes 2 barrel `hide` clauses) | delete | S | high |
| 5 | Rename `apps/desktop/.../targets_tab.dart:12 targetSearchProvider` → `sequenceTargetSearchProvider`; drop app-shim `framing_search_provider.dart` | rename | S | med |
| 6 | Split `screens/equipment/tabs/connections_tab.dart` (2,723 LOC) — one file per `_*DeviceCard` | split | S | med |
| 7 | Rename `equipment_models.dart:225 CameraState` → `CameraStateSnapshot` (kills `nightshade_core.dart:89 hide CameraState`) | rename | M | med |
| 8 | Rename framing `MosaicConfig`/`MosaicPanel` to `Framing*`; delete planetarium duplicates (kills barrel `hide` line 58) | rename + delete | M | med |
| 9 | Split `ascom/src/windows_impl.rs` (3,756 LOC) per device class | split | M | med |
| 10 | Split `screens/imaging/imaging_screen.dart` (7,079 LOC) per §1.2 table | split | M | med |
| 11 | Split `providers/sequence_provider.dart` — extract `SequenceExecutor` (~1,400 LOC) | split | M | med |
| 12 | Stop `nightshade_ui/.../polar_alignment_wizard.dart` from importing `nightshade_bridge/src/api.dart`/`event.dart` — worst layering violation | refactor | M | med |
| 13 | Re-expose drift `CapturedImage`/`EquipmentProfile` from core barrel as aliases instead of hiding (removes 4 `src/` bypasses) | refactor | S | med |
| 14 | Split `bridge/src/devices.rs` (8,854 LOC) per §1.2 | split | L | high |
| 15 | Split `bridge/src/api.rs` (9,770 LOC) per §1.2 | split | L | high |
| 16 | Split `nightshade_core` → `nightshade_data` + `nightshade_domain` per §7 | restructure | L | high |
| 17 | Stop committing `*.freezed.dart` + add regen hook | restructure | M | low |
| 18 | Delete duplicate `apps/desktop/lib/screens/framing/framing_search_provider.dart` (verify it has no desktop-specific logic first) | delete | S | low |

**Top-5 quick wins:** #1 (gitattributes, ~10min), #2 (UI enum dupes, ~30min), #4 (FocusDataPoint/PlateSolveResult, 1–2h), #3 (deprecated typedefs, 2–3h), #6 (split connections_tab, 1h).

---

## Appendix A — Verification commands run

```bash
git log -1 --format='%H %s'         # bbdee9b on worktree-agent-...
git ls-files | grep -E '\.(dart|rs|js|ts)$' | xargs wc -l | sort -rn | head -50
git ls-files | grep -E '\.(g|freezed)\.dart$|frb_generated' | xargs wc -l | sort -rn | head -30
git ls-files | grep -E '\.(g|freezed)\.dart$|frb_generated' | wc -l   # 64
git ls-files | grep -E '\.(dart|rs|js|ts)$' | xargs wc -l | awk '$1 > 2000' | sort -rn  # 38 files
grep -rnE "^import .+ hide " packages apps
grep -rnE "@Deprecated\(" packages apps
grep -rnE "^class HorizonProfile\b" packages apps   # not present
```

## Appendix B — Caveats

- LOC counts include comments and whitespace (raw `wc -l`).
- Deprecation usage counts for `DeviceInfo.type` are inconclusive without semantic analysis — `.type` is too common a token to grep.
- The reference commit `0c88691` is reachable but not the HEAD; the branch is ~50 commits past the W7 work referenced in the prompt. Several collisions the prompt mentioned (`HorizonProfile`, `FirstNightWizard`, `AnnotationPreset`) are no longer present.
