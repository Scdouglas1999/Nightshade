# Release PR Split Plan

- Source audit: `docs/production-readiness/release-staging-audit.json`
- Branch: `feature/v6-make-it-real`
- HEAD: `250049463`
- Entries assigned to proposed review buckets: `10217`
- Non-empty buckets: `10`
- Untracked release-critical entries: `55`
- Pathspec directory: `docs/production-readiness/release-pr-pathspecs`
- Draft PR descriptions: `docs/production-readiness/release-pr-drafts`
- Release decision lists: `docs/production-readiness/release-pr-lists`

This is a planning artifact. It does not stage files, create a branch, create a PR, or make the public release gate pass.

## Bucket Summary

| Suggested order | Bucket | Count | Untracked | Release-critical | Generated | Binary |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Generated Files | 31 | 1 | 20 | 31 | 0 |
| 2 | Binary And Evidence Artifacts | 17 | 0 | 0 | 0 | 17 |
| 3 | Release Infrastructure And Evidence | 71 | 1 | 71 | 0 | 0 |
| 4 | Headless Remote API And Dashboard | 87 | 5 | 85 | 0 | 0 |
| 5 | Mobile Remote Client | 57 | 16 | 32 | 0 | 0 |
| 6 | Native Driver And Bridge Source | 48 | 2 | 47 | 0 | 0 |
| 7 | Core Data Model And Services | 303 | 21 | 303 | 0 | 0 |
| 8 | Desktop UI And Workflow Packages | 513 | 39 | 430 | 0 | 0 |
| 9 | Tests And Support Tooling | 544 | 336 | 0 | 0 | 0 |
| 10 | Out Of Release Scope Review | 8546 | 8529 | 0 | 0 | 0 |

## Release Decision Lists

The lists below are mutually exclusive. Generated and binary/evidence paths are separated before release-critical source/docs paths so reviewers can stage those concern areas independently.

| List | Count | File | Description |
| --- | ---: | --- | --- |
| Must Ship | 968 | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | Release-critical source, docs, and tooling paths that are not generated outputs or binary/evidence artifacts. |
| Generated Only | 31 | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | Generated files that should be reviewed against their source changes and generator commands. |
| Binary And Evidence | 17 | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | Binary payloads, screenshots, APKs, DLLs, and other evidence artifacts that need explicit artifact review. |
| Defer Or Exclude | 9201 | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | Non-release-critical paths that need owner review before they are staged into a public release branch. |

## Proposed Review Buckets

### 1. Generated Files

- Bucket ID: `generated-files`
- Count: `31`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/01-generated-files.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Tracked changes: `30`
- Untracked: `1`
- Deleted: `0`
- Release-critical: `20`
- Intent: Review regenerated Dart, Drift, Freezed, bridge, and lock files apart from human-authored source.
- Recommended action: Regenerate from source, verify generator commands, then stage only outputs that correspond to reviewed model/API changes.

Category mix:

- `generated`: `31`

Examples:

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
- ... 1 more entries in JSON.

### 2. Binary And Evidence Artifacts

- Bucket ID: `binary-and-evidence-artifacts`
- Count: `17`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/02-binary-and-evidence-artifacts.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Tracked changes: `17`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `0`
- Intent: Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.
- Recommended action: Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

Category mix:

- `binary-native-artifact`: `17`

Examples:

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

### 3. Release Infrastructure And Evidence

- Bucket ID: `release-infra-evidence`
- Count: `71`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/03-release-infra-evidence.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Tracked changes: `70`
- Untracked: `1`
- Deleted: `16`
- Release-critical: `71`
- Intent: Keep release gates, production audit tools, public readiness docs, and operational docs together.
- Recommended action: Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

Category mix:

- `other`: `4`
- `release-evidence-docs`: `52`
- `release-tooling`: `15`

Examples:

- ` M` `.github/workflows/linux-release-build.yml` (other)
- ` M` `.github/workflows/release.yml` (other)
- ` M` `apps/desktop/linux/flutter/generated_plugin_registrant.cc` (other)
- ` M` `apps/desktop/linux/flutter/generated_plugins.cmake` (other)
- ` M` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- ` M` `docs/production-readiness/behavioral-audit-register.md` (release-evidence-docs)
- ` M` `docs/production-readiness/developer-quality-audit.json` (release-evidence-docs)
- ` M` `docs/production-readiness/developer-quality-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` (release-evidence-docs)
- ` M` `docs/production-readiness/fail-closed-audit.json` (release-evidence-docs)
- ` M` `docs/production-readiness/headless-api-contract-audit.json` (release-evidence-docs)
- ` M` `docs/production-readiness/headless-api-contract-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/highrisk-baseline.txt` (release-evidence-docs)
- ` M` `docs/production-readiness/linux-release-build-evidence.json` (release-evidence-docs)
- ` M` `docs/production-readiness/linux-release-package-metadata.json` (release-evidence-docs)
- ` M` `docs/production-readiness/linux-runtime-smoke.log` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-blocker-inputs.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-blocker-inputs.md` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-checklist-audit.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-checklist-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-completion-audit.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-completion-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-external-evidence.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-external-evidence.md` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-gate.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-gate.md` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-owner-checklist.json` (release-evidence-docs)
- ` M` `docs/production-readiness/public-release-owner-checklist.md` (release-evidence-docs)
- ` D` `docs/production-readiness/release-pr-drafts/01-binary-and-evidence-artifacts.md` (release-evidence-docs)
- ` D` `docs/production-readiness/release-pr-drafts/02-release-infra-evidence.md` (release-evidence-docs)
- ... 41 more entries in JSON.

### 4. Headless Remote API And Dashboard

- Bucket ID: `headless-remote-api`
- Count: `87`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/04-headless-remote-api.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Tracked changes: `82`
- Untracked: `5`
- Deleted: `0`
- Release-critical: `85`
- Intent: Review headless server routes, auth policy, dashboard assets, LAN behavior, and WebSocket changes as one API surface.
- Recommended action: Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

Category mix:

- `headless-remote`: `87`

Examples:

- ` M` `apps/desktop/lib/headless_api/auth/pairing_service.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/auth_policy.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/atlas_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/backup_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/calibration_handlers/dark_library_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/calibration_handlers/defect_map_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/calibration_library_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/catalog_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/coimaging_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/collaboration_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/db_read_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_discovery_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers/camera_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers/filter_wheel_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers/focuser_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers/mount_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers/rotator_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/dome_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/first_light_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/flat_wizard_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/focus_model_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/framing_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/guiding_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/mosaic_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/narrator_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/pairing_handlers.dart` (headless-remote)
- ... 57 more entries in JSON.

### 5. Mobile Remote Client

- Bucket ID: `mobile-remote-client`
- Count: `57`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/05-mobile-remote-client.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Tracked changes: `41`
- Untracked: `16`
- Deleted: `0`
- Release-critical: `32`
- Intent: Review Android/mobile remote-client code and mobile smoke tooling separately from desktop/headless server changes.
- Recommended action: Stage with Android build metadata and emulator smoke artifacts only after confirming the server API bucket it depends on is reviewed.

Category mix:

- `mobile`: `57`

Examples:

- `??` `apps/mobile/android/FCM_PUSH_SETUP.md` (mobile)
- ` M` `apps/mobile/android/app/build.gradle.kts` (mobile)
- ` M` `apps/mobile/android/app/src/main/AndroidManifest.xml` (mobile)
- ` M` `apps/mobile/android/app/src/main/kotlin/com/example/nightshade_mobile/MainActivity.kt` (mobile)
- `??` `apps/mobile/android/app/src/main/kotlin/com/example/nightshade_mobile/NightshadePushService.kt` (mobile)
- `??` `apps/mobile/android/app/src/main/kotlin/com/example/nightshade_mobile/PushBridge.kt` (mobile)
- ` M` `apps/mobile/android/gradle/wrapper/gradle-wrapper.properties` (mobile)
- ` M` `apps/mobile/android/settings.gradle.kts` (mobile)
- ` M` `apps/mobile/lib/main.dart` (mobile)
- ` M` `apps/mobile/lib/main_parts/mobile_connection_state.dart` (mobile)
- ` M` `apps/mobile/lib/main_parts/mobile_discovery_ops.dart` (mobile)
- ` M` `apps/mobile/lib/main_parts/mobile_reconnect_ops.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/mobile_dashboard_screen.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/camera_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/devices_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/log_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/mount_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/science_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/sequencer_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/dashboard/tabs/settings_tab.dart` (mobile)
- ` M` `apps/mobile/lib/screens/qr_scanner_screen.dart` (mobile)
- ` M` `apps/mobile/lib/screens/replay/session_picker_screen.dart` (mobile)
- ` M` `apps/mobile/lib/screens/replay/session_replay_screen.dart` (mobile)
- ` M` `apps/mobile/lib/screens/servers/saved_servers_screen.dart` (mobile)
- ` M` `apps/mobile/lib/screens/setup/first_run_setup_screen.dart` (mobile)
- `??` `apps/mobile/lib/services/android_system_ui.dart` (mobile)
- ` M` `apps/mobile/lib/services/live_activity_lifecycle_provider.dart` (mobile)
- `??` `apps/mobile/lib/services/manual_server_endpoint.dart` (mobile)
- ` M` `apps/mobile/lib/services/mobile_preferences.dart` (mobile)
- ` M` `apps/mobile/lib/services/mobile_sequence_hooks.dart` (mobile)
- ... 27 more entries in JSON.

### 6. Native Driver And Bridge Source

- Bucket ID: `native-driver-bridge`
- Count: `48`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/06-native-driver-bridge.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Tracked changes: `46`
- Untracked: `2`
- Deleted: `0`
- Release-critical: `47`
- Intent: Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.
- Recommended action: Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

Category mix:

- `bridge`: `15`
- `native-rust`: `33`

Examples:

- `??` `native/nightshade_native/bridge/src/api/devices/environment.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/devices/mod.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/devices/simulation.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/discovery.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/finishing_combine.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/imaging.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/plate_solve.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/polar_alignment.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/post_session.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/secondary_rig.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/sequencer.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api/storage.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper/rotator.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/connection.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/heartbeat.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/mod.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/ops/dome.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/ops/rotator.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/ops/safety.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_manager/ops/weather.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/frb_generated.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/real_device_ops.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/unified_device_ops.rs` (native-rust)
- ` M` `native/nightshade_native/imaging/Cargo.toml` (native-rust)
- ` M` `native/nightshade_native/imaging/src/platesolve.rs` (native-rust)
- ` M` `native/nightshade_native/sequencer/src/autofocus.rs` (native-rust)
- ` M` `native/nightshade_native/sequencer/src/dual_rig.rs` (native-rust)
- ` M` `native/nightshade_native/sequencer/src/instructions.rs` (native-rust)
- ` M` `native/nightshade_native/sequencer/src/lib.rs` (native-rust)
- ` M` `native/nightshade_native/sequencer/src/meridian_flip_executor.rs` (native-rust)
- ... 18 more entries in JSON.

### 7. Core Data Model And Services

- Bucket ID: `core-data-model`
- Count: `303`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/07-core-data-model.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Tracked changes: `282`
- Untracked: `21`
- Deleted: `0`
- Release-critical: `303`
- Intent: Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.
- Recommended action: Stage with focused tests and a release-authentic older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

Category mix:

- `core`: `303`

Examples:

- ` M` `packages/nightshade_core/lib/nightshade_core.dart` (core)
- ` M` `packages/nightshade_core/lib/nightshade_core_models.dart` (core)
- ` M` `packages/nightshade_core/lib/nightshade_core_providers.dart` (core)
- ` M` `packages/nightshade_core/lib/nightshade_core_services.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/disconnected_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend/bridge_model_mappers.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend/mount_guiding_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend/status_profile_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/device_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/domain_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/guiding_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/http_transport.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/imaging_profile_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/observing_list_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/planning_accessory_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/planning_data_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/post_session_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/remote_calibration_catalog_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/remote_database_plugin_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/remote_log_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/remote_operations.dart` (core)
- `??` `packages/nightshade_core/lib/src/backend/network_backend/replay_debug_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/sequencer_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/session_science_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/stacking_operations.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/wire_history_models.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend/wire_models.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/roles/device_backend.dart` (core)
- ... 273 more entries in JSON.

### 8. Desktop UI And Workflow Packages

- Bucket ID: `desktop-ui-workflows`
- Count: `513`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/08-desktop-ui-workflows.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Tracked changes: `474`
- Untracked: `39`
- Deleted: `1`
- Release-critical: `430`
- Intent: Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.
- Recommended action: Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

Category mix:

- `app-ui`: `430`
- `other`: `9`
- `planetarium`: `18`
- `plugins`: `8`
- `remote-protocol`: `15`
- `ui-system`: `18`
- `updater`: `15`

Examples:

- ` M` `apps/desktop/lib/desktop_app_bootstrap.dart` (other)
- `??` `apps/desktop/lib/headless/headless_auto_connect_bootstrap.dart` (other)
- ` M` `apps/desktop/lib/headless/headless_disk_watchdog_bootstrap.dart` (other)
- ` M` `apps/desktop/lib/headless/headless_services_bootstrap.dart` (other)
- `??` `apps/desktop/lib/headless/headless_shutdown.dart` (other)
- ` M` `apps/desktop/lib/main.dart` (other)
- ` M` `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` (other)
- ` M` `apps/desktop/lib/screens/sequencer/tabs/targets_tab/targets_header.dart` (other)
- ` D` `apps/desktop/lib/widgets/update_manager.dart` (other)
- ` M` `packages/nightshade_app/lib/app.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/localization/nightshade_localizations/translations.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/nightshade_app.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/router/app_router.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen/equipment_stats.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen/history_cards.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen/history_tab.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen/session_detail_dialog.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen/session_tab.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/image_grader_dialog.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/image_thumbnail_strip.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/mpc_export_panel.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/night_story_timeline.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/period_analysis_panel.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/coefficients.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/frame_selection.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/save_navigation.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/star_matching.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/project_tracking_panel.dart` (app-ui)
- ... 483 more entries in JSON.

### 9. Tests And Support Tooling

- Bucket ID: `tests-and-support-tooling`
- Count: `544`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/09-tests-and-support-tooling.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Tracked changes: `208`
- Untracked: `336`
- Deleted: `0`
- Release-critical: `0`
- Intent: Review non-release test files, scripts, package config, and developer tooling separately from product behavior.
- Recommended action: Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

Category mix:

- `package-config`: `3`
- `tests`: `540`
- `tooling`: `1`

Examples:

- ` M` `apps/desktop/pubspec.yaml` (package-config)
- `??` `apps/desktop/test/headless/headless_auto_connect_bootstrap_test.dart` (tests)
- `??` `apps/desktop/test/headless/headless_shutdown_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/analytics_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/atlas_handlers_error_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/auth_middleware_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/auth_policy_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/backup_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/calibration_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/calibration_library_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/camera_cooling_handler_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/camera_recommended_settings_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/coimaging_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/collaboration_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/db_read_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/device_discovery_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/device_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/fail_closed_auth_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/first_light_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/flat_wizard_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/focus_model_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/focuser_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/framing_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/guiding_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/handler_test_helpers.dart` (tests)
- ` M` `apps/desktop/test/headless_api/headless_plugin_node_dispatch_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/imaging_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/narrator_handlers_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/network_backend_contract_test.dart` (tests)
- ` M` `apps/desktop/test/headless_api/pairing_handlers_test.dart` (tests)
- ... 514 more entries in JSON.

### 10. Out Of Release Scope Review

- Bucket ID: `out-of-release-scope-review`
- Count: `8546`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/10-out-of-release-scope-review.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Tracked changes: `17`
- Untracked: `8529`
- Deleted: `0`
- Release-critical: `0`
- Intent: Quarantine scratch reports, research files, goal tracking, and broad miscellaneous edits until they are explicitly accepted or excluded.
- Recommended action: Do not stage into the public release branch without owner review and an explicit reason.

Category mix:

- `docs`: `7`
- `other`: `8539`

Examples:

- `??` `.codex-nightshade-window.js` (other)
- `??` `.codex-window-list.js` (other)
- `??` `.narrative_hits.txt` (other)
- ` M` `README.md` (other)
- ` M` `apps/desktop/macos/Flutter/GeneratedPluginRegistrant.swift` (other)
- ` M` `apps/desktop/windows/flutter/generated_plugin_registrant.cc` (other)
- ` M` `apps/desktop/windows/flutter/generated_plugins.cmake` (other)
- ` M` `docs/THIRD_PARTY_NOTICES.md` (docs)
- ` M` `docs/architecture.md` (docs)
- ` M` `docs/architecture/plugin-sequence-nodes.md` (docs)
- ` M` `docs/getting-started/installation.md` (docs)
- ` M` `docs/release-smoke-test.md` (docs)
- `??` `docs/releases/README.md` (docs)
- `??` `docs/releases/v6.0.0-README.md` (docs)
- `??` `graphify-out/.graphify_detect.err` (other)
- `??` `graphify-out/.graphify_labels.json` (other)
- `??` `graphify-out/.graphify_python` (other)
- `??` `graphify-out/.graphify_root` (other)
- `??` `graphify-out/2026-06-29/.graphify_labels.json` (other)
- `??` `graphify-out/2026-06-29/GRAPH_REPORT.md` (other)
- `??` `graphify-out/2026-06-29/cost.json` (other)
- `??` `graphify-out/2026-06-29/graph.json` (other)
- `??` `graphify-out/2026-06-29/manifest.json` (other)
- `??` `graphify-out/2026-06-30/.graphify_labels.json` (other)
- `??` `graphify-out/2026-06-30/GRAPH_REPORT.md` (other)
- `??` `graphify-out/2026-06-30/cost.json` (other)
- `??` `graphify-out/2026-06-30/graph.json` (other)
- `??` `graphify-out/2026-06-30/manifest.json` (other)
- `??` `graphify-out/2026-07-01/.graphify_labels.json` (other)
- `??` `graphify-out/2026-07-01/GRAPH_REPORT.md` (other)
- ... 8516 more entries in JSON.

## Release Branch Implication

A clean public release branch still requires each bucket to be staged, excluded, or split into smaller PRs intentionally. The current branch remains `feature/v6-make-it-real`, so this plan is evidence for scoping only, not release readiness.
