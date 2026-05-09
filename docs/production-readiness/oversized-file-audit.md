# Oversized File Audit

- Scanned files: `716`
- Warning threshold: `1000` lines
- Critical threshold: `2500` lines
- Warning files: `65`
- Critical files: `16`
- Priority split candidates: `6`

This audit finds large hand-authored Dart files so refactors can be planned deliberately. Generated, vendored, build, and mock files are excluded.

## Critical Files

| Lines | Path |
| ---: | --- |
| 5339 | `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart` |
| 4746 | `packages/nightshade_webrtc/lib/src/web_server.dart` |
| 4688 | `packages/nightshade_app/lib/screens/framing/framing_screen.dart` |
| 4003 | `packages/nightshade_bridge/lib/src/api.dart` |
| 3943 | `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` |
| 3798 | `packages/nightshade_core/lib/src/backend/network_backend.dart` |
| 3790 | `packages/nightshade_core/lib/src/providers/sequence_provider.dart` |
| 3731 | `packages/nightshade_bridge/lib/src/bridge_stub.dart` |
| 3155 | `packages/nightshade_core/lib/src/services/device_service.dart` |
| 3033 | `packages/nightshade_planetarium/lib/src/catalogs/constellation_data.dart` |
| 2981 | `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` |
| 2966 | `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` |
| 2828 | `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` |
| 2751 | `packages/nightshade_core/lib/src/backend/ffi_backend.dart` |
| 2709 | `packages/nightshade_app/lib/screens/sequencer/widgets/instruction_node_properties.dart` |
| 2555 | `apps/desktop/lib/headless_api_server.dart` |

## Priority Split Candidates

| Lines | Path | Reason |
| ---: | --- | --- |
| 4746 | `packages/nightshade_webrtc/lib/src/web_server.dart` | WebRTC server routing, API helpers, and dashboard docs are concentrated in one backend file. |
| 3798 | `packages/nightshade_core/lib/src/backend/network_backend.dart` | Remote client endpoint coverage and response parsing are concentrated in NetworkBackend. |
| 3790 | `packages/nightshade_core/lib/src/providers/sequence_provider.dart` | Sequencer state, validation, and execution logic are concentrated in one provider. |
| 3155 | `packages/nightshade_core/lib/src/services/device_service.dart` | Cross-device command orchestration is large enough to hide device-specific regressions. |
| 2751 | `packages/nightshade_core/lib/src/backend/ffi_backend.dart` | Native backend command paths are large enough to make hardware workflow edits risky. |
| 2555 | `apps/desktop/lib/headless_api_server.dart` | Headless route registration, middleware, self-test, and static serving share one release-critical file. |

## Largest Files

| Lines | Path |
| ---: | --- |
| 5339 | `packages/nightshade_planetarium/lib/src/rendering/sky_renderer.dart` |
| 4746 | `packages/nightshade_webrtc/lib/src/web_server.dart` |
| 4688 | `packages/nightshade_app/lib/screens/framing/framing_screen.dart` |
| 4003 | `packages/nightshade_bridge/lib/src/api.dart` |
| 3943 | `packages/nightshade_app/lib/screens/sequencer/tabs/templates_tab.dart` |
| 3798 | `packages/nightshade_core/lib/src/backend/network_backend.dart` |
| 3790 | `packages/nightshade_core/lib/src/providers/sequence_provider.dart` |
| 3731 | `packages/nightshade_bridge/lib/src/bridge_stub.dart` |
| 3155 | `packages/nightshade_core/lib/src/services/device_service.dart` |
| 3033 | `packages/nightshade_planetarium/lib/src/catalogs/constellation_data.dart` |
| 2981 | `packages/nightshade_core/lib/src/models/sequence/sequence_models.dart` |
| 2966 | `packages/nightshade_app/lib/screens/polar_alignment/polar_alignment_screen.dart` |
| 2828 | `packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart` |
| 2751 | `packages/nightshade_core/lib/src/backend/ffi_backend.dart` |
| 2709 | `packages/nightshade_app/lib/screens/sequencer/widgets/instruction_node_properties.dart` |
| 2555 | `apps/desktop/lib/headless_api_server.dart` |
| 2442 | `packages/nightshade_app/lib/screens/sequencer/widgets/sequence_tree.dart` |
| 2351 | `packages/nightshade_app/lib/screens/settings/equipment_profiles_screen.dart` |
| 2293 | `packages/nightshade_app/lib/screens/imaging/tabs/focus_tab.dart` |
| 2227 | `packages/nightshade_core/lib/src/providers/settings_provider.dart` |
| 2210 | `packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart` |
| 2181 | `packages/nightshade_app/lib/screens/analytics/widgets/science_analytics_tab.dart` |
| 2141 | `packages/nightshade_app/lib/screens/imaging/widgets/annotation_panel.dart` |
| 2076 | `packages/nightshade_app/lib/screens/sequencer/widgets/quick_start_wizard_dialog.dart` |
| 2004 | `packages/nightshade_core/lib/src/models/tutorial/tutorial_models.dart` |
| 1963 | `packages/nightshade_planetarium/lib/src/providers/planetarium_providers.dart` |
| 1948 | `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card.dart` |
| 1771 | `packages/nightshade_core/lib/src/providers/framing_provider.dart` |
| 1725 | `packages/nightshade_app/lib/screens/sequencer/sequencer_screen.dart` |
| 1683 | `packages/nightshade_core/lib/src/services/science/default_science_backend.dart` |
| 1674 | `packages/nightshade_app/lib/screens/planetarium/planetarium_screen.dart` |
| 1571 | `packages/nightshade_app/lib/screens/diagnostics/diagnostics_screen.dart` |
| 1568 | `packages/nightshade_app/lib/screens/settings/widgets/autofocus_settings.dart` |
| 1558 | `packages/nightshade_core/lib/src/database/database.dart` |
| 1540 | `packages/nightshade_core/lib/src/providers/equipment_provider.dart` |
| 1518 | `apps/desktop/lib/main.dart` |
| 1479 | `packages/nightshade_planetarium/lib/src/widgets/object_details_panel.dart` |
| 1474 | `packages/nightshade_planetarium/lib/src/catalogs/catalog_manager.dart` |
| 1473 | `packages/nightshade_app/lib/screens/planetarium/widgets/mobile_widgets.dart` |
| 1422 | `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` |
| 1416 | `packages/nightshade_planetarium/lib/src/catalogs/variable_star_catalog.dart` |
| 1401 | `packages/nightshade_app/lib/screens/weather/weather_screen.dart` |
| 1338 | `packages/nightshade_app/lib/screens/planner/planner_screen.dart` |
| 1338 | `packages/nightshade_app/lib/screens/sequencer/widgets/snippet_palette.dart` |
| 1337 | `packages/nightshade_app/lib/screens/imaging/tabs/capture_tab.dart` |
| 1333 | `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` |
| 1333 | `packages/nightshade_planetarium/lib/src/catalogs/constellation_art.dart` |
| 1325 | `packages/nightshade_app/lib/screens/imaging/widgets/overlay_painters.dart` |
| 1318 | `packages/nightshade_app/lib/screens/sequencer/widgets/node_progress_panels.dart` |
| 1312 | `packages/nightshade_app/lib/screens/imaging/tabs/camera_tab.dart` |
