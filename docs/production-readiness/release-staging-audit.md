# Release Staging Audit

- Branch: `feature/v6-make-it-real`
- HEAD: `250049463`
- Total changed/untracked entries: `10217`
- Tracked modified/added/deleted entries: `1267`
- Untracked entries: `8950`
- Deleted entries: `17`
- Generated entries: `31`
- Binary/evidence/native artifact entries: `17`
- Untracked release-critical entries: `55`

This is a scoping report only. It does not make the worktree clean and does not prove a release branch or PR has been created.

## Category Summary

| Category | Count | Untracked |
| --- | ---: | ---: |
| app-ui | 430 | 23 |
| binary-native-artifact | 17 | 0 |
| bridge | 15 | 1 |
| core | 303 | 21 |
| docs | 7 | 2 |
| generated | 31 | 1 |
| headless-remote | 87 | 5 |
| mobile | 57 | 16 |
| native-rust | 33 | 1 |
| other | 8552 | 8529 |
| package-config | 3 | 0 |
| planetarium | 18 | 5 |
| plugins | 8 | 0 |
| release-evidence-docs | 52 | 0 |
| release-tooling | 15 | 1 |
| remote-protocol | 15 | 3 |
| tests | 540 | 336 |
| tooling | 1 | 0 |
| ui-system | 18 | 3 |
| updater | 15 | 3 |

## Required Split Before PR

- Review generated files separately from human-authored source.
- Review binary/native artifacts separately from source diffs.
- Stage release evidence docs and production tools intentionally; many are untracked.
- Do not cut a public tag from this worktree until untracked release-critical entries are either staged or explicitly excluded.


## Untracked Release-Critical Entries

- `??` `apps/desktop/lib/headless_api/handlers/coimaging_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/replay_debug_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/routes/coimaging_routes.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/routes/replay_debug_routes.dart` (headless-remote)
- `??` `apps/desktop/web_dashboard/test/api_contract_test.js` (headless-remote)
- `??` `apps/mobile/lib/services/android_system_ui.dart` (mobile)
- `??` `apps/mobile/lib/services/manual_server_endpoint.dart` (mobile)
- `??` `native/nightshade_native/bridge/src/api/devices/environment.rs` (native-rust)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/coimaging_create_sheet.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/collab_mosaic_detail_screen.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/collaborative_sky_format.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/collaborative_sky_providers.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/collaborative_sky_screen.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/widgets/coimaging_session_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/widgets/collab_mosaic_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/collaborative_sky/widgets/shared_library_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/mosaic/mosaic_contribute_sheet.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/onboarding/steps/site_step.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/planetarium/providers/finder_chart_catalog_provider.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/settings/backup_list_entry.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/shell/shell_back_dispatcher.dart` (app-ui)
- `??` `packages/nightshade_app/lib/services/file_download_service.dart` (app-ui)
- `??` `packages/nightshade_app/lib/services/image_download_service.dart` (app-ui)
- `??` `packages/nightshade_app/lib/services/plugin_runtime_bootstrap.dart` (app-ui)
- `??` `packages/nightshade_app/lib/utils/authority_bound_dialog.dart` (app-ui)
- `??` `packages/nightshade_app/lib/utils/cooled_camera_guard.dart` (app-ui)
- `??` `packages/nightshade_app/lib/utils/exported_file_reveal.dart` (app-ui)
- `??` `packages/nightshade_app/lib/utils/startup_surface_coordinator.dart` (app-ui)
- `??` `packages/nightshade_app/lib/utils/startup_ui_context.dart` (app-ui)
- `??` `packages/nightshade_app/lib/widgets/auto_integration_launcher.dart` (app-ui)
- `??` `packages/nightshade_app/lib/widgets/startup_auto_connect_launcher.dart` (app-ui)
- `??` `packages/nightshade_bridge/lib/src/api/devices/environment.dart` (bridge)
- `??` `packages/nightshade_core/lib/src/backend/network_backend/replay_debug_operations.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/coimaging_sessions_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/coimaging_sessions_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/database/migration_v56.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/database/migration_v57.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/tables/coimaging_sessions.dart` (core)
- `??` `packages/nightshade_core/lib/src/models/calibration/shared_calibration_models.dart` (core)
- `??` `packages/nightshade_core/lib/src/models/collaboration/collaboration_models.dart` (core)
- `??` `packages/nightshade_core/lib/src/models/equipment_profile_validation.dart` (core)
- `??` `packages/nightshade_core/lib/src/models/flat_wizard/flat_capture_config.dart` (core)
- `??` `packages/nightshade_core/lib/src/providers/focus_model_profile_data_provider.dart` (core)
- `??` `packages/nightshade_core/lib/src/providers/sequence/rules/plugin_node_rules.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/calibration/shared_calibration_client.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/calibration/shared_calibration_library.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/coimaging/coimaging_session_service.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/endpoint_sanitizer.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/import/target_library_importer.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/mosaic/collaborative_mosaic_poller.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/mosaic/collaborative_mosaic_service.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/mosaic/mosaic_upload_consent.dart` (core)
- `??` `packages/nightshade_core/lib/src/services/remote_sequence_editor_sync_lifecycle.dart` (core)
- `??` `packages/nightshade_core/lib/src/utils/resilient_poll_stream.dart` (core)
- `??` `tools/production/full_hardware_control_smoke.dart` (release-tooling)

## Binary / Evidence Artifact Entries

- ` M` `assets/screenshots/analytics.png` (binary-native-artifact)
- ` M` `assets/screenshots/desktop-dashboard.png` (binary-native-artifact)
- ` M` `assets/screenshots/equipment.png` (binary-native-artifact)
- ` M` `assets/screenshots/flat-wizard.png` (binary-native-artifact)
- ` M` `assets/screenshots/framing.png` (binary-native-artifact)
- ` M` `assets/screenshots/guiding.png` (binary-native-artifact)
- ` M` `assets/screenshots/imaging.png` (binary-native-artifact)
- ` M` `assets/screenshots/plan-tonight.png` (binary-native-artifact)
- ` M` `assets/screenshots/planetarium.png` (binary-native-artifact)
- ` M` `assets/screenshots/sequencer.png` (binary-native-artifact)
- ` M` `assets/screenshots/settings-equipment-profiles.png` (binary-native-artifact)
- ` M` `assets/screenshots/weather.png` (binary-native-artifact)
- ` M` `docs/design/goldens/morning-report-sub-cull-rail.png` (binary-native-artifact)
- ` M` `docs/design/goldens/morning-report-workbench.png` (binary-native-artifact)
- ` M` `docs/design/goldens/mosaic-project-complete.png` (binary-native-artifact)
- ` M` `docs/design/goldens/surface-run-session-progress.png` (binary-native-artifact)
- ` M` `docs/design/goldens/surface-settings-appearance.png` (binary-native-artifact)

## Generated Entries

- ` M` `apps/desktop/pubspec.lock` (generated)
- ` M` `apps/mobile/pubspec.lock` (generated)
- ` M` `apps/mobile_e2e/pubspec.lock` (generated)
- ` M` `native/nightshade_native/Cargo.lock` (generated)
- ` M` `packages/nightshade_bridge/ios/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.io.dart` (generated)
- ` M` `packages/nightshade_bridge/linux/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/macos/bridge_generated.h` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/coimaging_sessions_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/database.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/alerts/transient_alert.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/flat_wizard/flat_wizard_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/imaging/auto_stretch_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/meridian_flip_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/optical_config.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/phd2_models.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/polar_alignment_config.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/polar_alignment_config.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/sequence/template_snippet.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/settings/app_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/settings/app_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/cloud_motion.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/radar_frame.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/weather_alert.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/weather_status.freezed.dart` (generated)
- ` M` `packages/nightshade_core/pubspec.lock` (generated)
- ` M` `packages/nightshade_remote_protocol/lib/src/database/pairing_database.g.dart` (generated)
- ` M` `packages/nightshade_ui/pubspec.lock` (generated)
- ` M` `packages/nightshade_updater/lib/src/models/update_state.freezed.dart` (generated)
- ` M` `packages/nightshade_updater/pubspec.lock` (generated)
