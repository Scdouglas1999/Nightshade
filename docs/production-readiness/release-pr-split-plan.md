# Release PR Split Plan

- Source audit: `docs/production-readiness/release-staging-audit.json`
- Branch: `main`
- HEAD: `bbdee9b`
- Entries assigned to proposed review buckets: `913`
- Non-empty buckets: `10`
- Untracked release-critical entries: `336`
- Pathspec directory: `docs/production-readiness/release-pr-pathspecs`
- Draft PR descriptions: `docs/production-readiness/release-pr-drafts`
- Release decision lists: `docs/production-readiness/release-pr-lists`

This is a planning artifact. It does not stage files, create a branch, create a PR, or make the public release gate pass.

## Bucket Summary

| Suggested order | Bucket | Count | Untracked | Release-critical | Generated | Binary |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Generated Files | 35 | 4 | 22 | 35 | 0 |
| 2 | Binary And Evidence Artifacts | 31 | 29 | 4 | 0 | 31 |
| 3 | Release Infrastructure And Evidence | 164 | 159 | 163 | 0 | 0 |
| 4 | Headless Remote API And Dashboard | 34 | 5 | 34 | 0 | 0 |
| 5 | Mobile Remote Client | 9 | 0 | 7 | 0 | 0 |
| 6 | Native Driver And Bridge Source | 100 | 13 | 100 | 0 | 0 |
| 7 | Core Data Model And Services | 127 | 45 | 127 | 0 | 0 |
| 8 | Desktop UI And Workflow Packages | 292 | 135 | 204 | 0 | 0 |
| 9 | Tests And Support Tooling | 64 | 50 | 0 | 0 | 0 |
| 10 | Out Of Release Scope Review | 57 | 44 | 0 | 0 | 0 |

## Release Decision Lists

The lists below are mutually exclusive. Generated and binary/evidence paths are separated before release-critical source/docs paths so reviewers can stage those concern areas independently.

| List | Count | File | Description |
| --- | ---: | --- | --- |
| Must Ship | 635 | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | Release-critical source, docs, and tooling paths that are not generated outputs or binary/evidence artifacts. |
| Generated Only | 35 | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | Generated files that should be reviewed against their source changes and generator commands. |
| Binary And Evidence | 31 | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | Binary payloads, screenshots, APKs, DLLs, and other evidence artifacts that need explicit artifact review. |
| Defer Or Exclude | 212 | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | Non-release-critical paths that need owner review before they are staged into a public release branch. |

## Proposed Review Buckets

### 1. Generated Files

- Bucket ID: `generated-files`
- Count: `35`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/01-generated-files.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-generated-files.txt`
- Tracked changes: `31`
- Untracked: `4`
- Deleted: `0`
- Release-critical: `22`
- Intent: Review regenerated Dart, Drift, Freezed, bridge, and lock files apart from human-authored source.
- Recommended action: Regenerate from source, verify generator commands, then stage only outputs that correspond to reviewed model/API changes.

Category mix:

- `generated`: `35`

Examples:

- ` M` `apps/desktop/pubspec.lock` (generated)
- ` M` `apps/mobile/pubspec.lock` (generated)
- ` M` `packages/nightshade_bridge/ios/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/lib/src/error.freezed.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/event.freezed.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.dart` (generated)
- ` M` `packages/nightshade_bridge/lib/src/frb_generated.io.dart` (generated)
- ` M` `packages/nightshade_bridge/linux/bridge_generated.h` (generated)
- ` M` `packages/nightshade_bridge/macos/bridge_generated.h` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/dark_library_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/flat_history_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/observation_logs_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/observing_lists_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/polar_alignment_history_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/daos/science_dao.g.dart` (generated)
- `??` `packages/nightshade_core/lib/src/database/daos/sequence_runs_dao.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/database/database.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/annotation_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/annotation_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/equipment_profile.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/equipment_profile.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/meridian_flip_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/meridian_flip_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/polar_alignment_config.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/polar_alignment_config.g.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/weather_settings.freezed.dart` (generated)
- ` M` `packages/nightshade_core/lib/src/models/weather/weather_settings.g.dart` (generated)
- ` M` `packages/nightshade_core/pubspec.lock` (generated)
- ` M` `packages/nightshade_planetarium/pubspec.lock` (generated)
- ` M` `packages/nightshade_plugins/pubspec.lock` (generated)
- ... 5 more entries in JSON.

### 2. Binary And Evidence Artifacts

- Bucket ID: `binary-and-evidence-artifacts`
- Count: `31`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/02-binary-and-evidence-artifacts.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt`
- Tracked changes: `2`
- Untracked: `29`
- Deleted: `0`
- Release-critical: `4`
- Intent: Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.
- Recommended action: Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

Category mix:

- `binary-native-artifact`: `27`
- `release-evidence-binary`: `4`

Examples:

- ` M` `apps/desktop/nightshade_bridge.dll` (binary-native-artifact)
- ` M` `apps/desktop/windows/nightshade_bridge.dll` (binary-native-artifact)
- `??` `docs/production-readiness/android-emulator-launch-smoke.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke-latest.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke-start.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke.png` (release-evidence-binary)
- `??` `report/gui-after-planner-pass.png` (binary-native-artifact)
- `??` `report/gui-after-skip.png` (binary-native-artifact)
- `??` `report/gui-analytics.png` (binary-native-artifact)
- `??` `report/gui-dashboard-after-action-state.png` (binary-native-artifact)
- `??` `report/gui-dashboard.png` (binary-native-artifact)
- `??` `report/gui-diagnostics-deep.png` (binary-native-artifact)
- `??` `report/gui-diagnostics.png` (binary-native-artifact)
- `??` `report/gui-equipment.png` (binary-native-artifact)
- `??` `report/gui-flat-wizard-after-disable.png` (binary-native-artifact)
- `??` `report/gui-flat-wizard-deep.png` (binary-native-artifact)
- `??` `report/gui-guiding-deep.png` (binary-native-artifact)
- `??` `report/gui-imaging.png` (binary-native-artifact)
- `??` `report/gui-initial.png` (binary-native-artifact)
- `??` `report/gui-planetarium.png` (binary-native-artifact)
- `??` `report/gui-planner-after-fix.png` (binary-native-artifact)
- `??` `report/gui-planner.png` (binary-native-artifact)
- `??` `report/gui-polar-alignment-deep.png` (binary-native-artifact)
- `??` `report/gui-sequencer-deep.png` (binary-native-artifact)
- `??` `report/gui-sequencer.png` (binary-native-artifact)
- `??` `report/gui-settings-fixed.png` (binary-native-artifact)
- `??` `report/gui-settings.png` (binary-native-artifact)
- `??` `report/gui-transients-deep.png` (binary-native-artifact)
- `??` `report/gui-transients-route-deep.png` (binary-native-artifact)
- `??` `report/gui-weather.png` (binary-native-artifact)
- ... 1 more entries in JSON.

### 3. Release Infrastructure And Evidence

- Bucket ID: `release-infra-evidence`
- Count: `164`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/03-release-infra-evidence.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt`
- Tracked changes: `5`
- Untracked: `159`
- Deleted: `0`
- Release-critical: `163`
- Intent: Keep release gates, production audit tools, public readiness docs, and operational docs together.
- Recommended action: Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

Category mix:

- `docs`: `5`
- `other`: `1`
- `package-config`: `1`
- `release-evidence-docs`: `98`
- `release-tooling`: `59`

Examples:

- `??` `docs/headless-secure-setup.md` (docs)
- `??` `docs/known-limitations.md` (docs)
- `??` `docs/migration-backup-restore.md` (docs)
- `??` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/dependency-hygiene.json` (release-evidence-docs)
- `??` `docs/production-readiness/dependency-hygiene.md` (release-evidence-docs)
- `??` `docs/production-readiness/developer-quality-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/developer-quality-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/docs-link-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/docs-link-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json` (release-evidence-docs)
- `??` `docs/production-readiness/fail-closed-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/fail-closed-audit.md` (release-evidence-docs)
- ` M` `docs/production-readiness/feature-parity-matrix.md` (release-evidence-docs)
- `??` `docs/production-readiness/hardware-availability-probe.json` (release-evidence-docs)
- `??` `docs/production-readiness/hardware-availability-probe.md` (release-evidence-docs)
- `??` `docs/production-readiness/headless-api-contract-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/headless-api-contract-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/headless-response-helper-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/headless-response-helper-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/headless-route-policy-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/headless-route-policy-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/linux-environment-probe.json` (release-evidence-docs)
- `??` `docs/production-readiness/linux-environment-probe.md` (release-evidence-docs)
- ... 134 more entries in JSON.

### 4. Headless Remote API And Dashboard

- Bucket ID: `headless-remote-api`
- Count: `34`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/04-headless-remote-api.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt`
- Tracked changes: `29`
- Untracked: `5`
- Deleted: `0`
- Release-critical: `34`
- Intent: Review headless server routes, auth policy, dashboard assets, LAN behavior, and WebSocket changes as one API surface.
- Recommended action: Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

Category mix:

- `headless-remote`: `34`

Examples:

- `??` `apps/desktop/lib/headless_api/auth_policy.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/backup_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/device_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/equipment_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/flat_wizard_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/focus_model_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/framing_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/guiding_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/mosaic_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/planetarium_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/profile_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/safety_monitor_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/scheduler_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/science_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/sequence_management_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/sequencer_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/session_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/suggestion_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/target_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/transient_handlers.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api/handlers/weather_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/response_helpers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/route_metadata.dart` (headless-remote)
- ` M` `apps/desktop/lib/headless_api_server.dart` (headless-remote)
- ` M` `apps/desktop/lib/main_headless.dart` (headless-remote)
- ... 4 more entries in JSON.

### 5. Mobile Remote Client

- Bucket ID: `mobile-remote-client`
- Count: `9`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/05-mobile-remote-client.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt`
- Tracked changes: `9`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `7`
- Intent: Review Android/mobile remote-client code and mobile smoke tooling separately from desktop/headless server changes.
- Recommended action: Stage with Android build metadata and emulator smoke artifacts only after confirming the server API bucket it depends on is reviewed.

Category mix:

- `mobile`: `9`

Examples:

- ` M` `apps/mobile/lib/main.dart` (mobile)
- ` M` `apps/mobile/lib/screens/qr_scanner_screen.dart` (mobile)
- ` M` `apps/mobile/lib/services/foreground_service.dart` (mobile)
- ` M` `apps/mobile/lib/services/mobile_sequence_hooks.dart` (mobile)
- ` M` `apps/mobile/lib/services/notification_service.dart` (mobile)
- ` M` `apps/mobile/lib/widgets/checkpoint_resume_dialog.dart` (mobile)
- ` M` `apps/mobile/lib/widgets/network_status_indicator.dart` (mobile)
- ` M` `apps/mobile/pubspec.yaml` (mobile)
- ` M` `apps/mobile/test/widget_test.dart` (mobile)

### 6. Native Driver And Bridge Source

- Bucket ID: `native-driver-bridge`
- Count: `100`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/06-native-driver-bridge.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt`
- Tracked changes: `87`
- Untracked: `13`
- Deleted: `1`
- Release-critical: `100`
- Intent: Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.
- Recommended action: Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

Category mix:

- `bridge`: `5`
- `native-rust`: `95`

Examples:

- ` M` `native/nightshade_native/Cargo.toml` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/camera.rs` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/client.rs` (native-rust)
- ` M` `native/nightshade_native/alpaca/src/telescope.rs` (native-rust)
- ` M` `native/nightshade_native/ascom/src/windows_impl.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/adaptive_polling.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/api.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_covercalibrator.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_filterwheel.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/ascom_wrapper_mount.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_rotator.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_safetymonitor.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_weather.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/builtin_guider.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/device_id.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/devices.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/error.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/event.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/filter_matching.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/frb_generated.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/lib.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/real_device_ops.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/sequencer_api.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/sequencer_ops.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/stacking_api.rs` (native-rust)
- ` M` `native/nightshade_native/bridge/src/unified_device_ops.rs` (native-rust)
- ` M` `native/nightshade_native/imaging/Cargo.toml` (native-rust)
- ` M` `native/nightshade_native/imaging/build.rs` (native-rust)
- ` M` `native/nightshade_native/imaging/src/buffer_pool.rs` (native-rust)
- ... 70 more entries in JSON.

### 7. Core Data Model And Services

- Bucket ID: `core-data-model`
- Count: `127`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/07-core-data-model.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt`
- Tracked changes: `82`
- Untracked: `45`
- Deleted: `0`
- Release-critical: `127`
- Intent: Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.
- Recommended action: Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

Category mix:

- `core`: `127`

Examples:

- ` M` `packages/nightshade_core/lib/nightshade_core.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/disconnected_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/network_backend.dart` (core)
- ` M` `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/dark_library_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/equipment_profiles_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/flat_history_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/images_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/observation_logs_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/observing_lists_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/polar_alignment_history_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/science_dao.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/daos/sequence_runs_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/sequences_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/sessions_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/targets_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/daos/weather_settings_dao.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/database.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/captured_images.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/tables/dark_library.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/flat_history.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/imaging_sessions.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/tables/observation_logs.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/tables/observing_lists.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/polar_alignment_history.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/science.dart` (core)
- `??` `packages/nightshade_core/lib/src/database/tables/sequence_runs.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/targets.dart` (core)
- ` M` `packages/nightshade_core/lib/src/database/tables/weather_settings.dart` (core)
- ... 97 more entries in JSON.

### 8. Desktop UI And Workflow Packages

- Bucket ID: `desktop-ui-workflows`
- Count: `292`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/08-desktop-ui-workflows.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt`
- Tracked changes: `157`
- Untracked: `135`
- Deleted: `1`
- Release-critical: `204`
- Intent: Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.
- Recommended action: Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

Category mix:

- `app-ui`: `204`
- `other`: `4`
- `planetarium`: `29`
- `plugins`: `11`
- `ui-system`: `18`
- `updater`: `10`
- `webrtc`: `16`

Examples:

- ` M` `apps/desktop/lib/main.dart` (other)
- ` M` `apps/desktop/lib/screens/framing/framing_search_provider.dart` (other)
- ` M` `apps/desktop/lib/screens/sequencer/tabs/targets_tab.dart` (other)
- ` M` `apps/desktop/lib/widgets/update_manager.dart` (other)
- ` M` `packages/nightshade_app/lib/app.dart` (app-ui)
- `??` `packages/nightshade_app/lib/localization/nightshade_localizations.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/router/app_router.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/analytics_screen.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/image_thumbnail_strip.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/mpc_export_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/period_analysis_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/project_tracking_panel.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/quick_csv_export.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_analytics_tab.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/analytics/widgets/science_export_hub.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_insights_panel.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/analytics/widgets/science_overlay_composer.dart` (app-ui)
- ` M` `packages/nightshade_app/lib/screens/dashboard/dashboard_screen.dart` (app-ui)
- ` D` `packages/nightshade_app/lib/screens/dashboard/dashboard_widgets.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/alerts_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/capture_settings_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/command_bar.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/dashboard_header_actions.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/dashboard_tile.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/dashboard_widget_registry.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/equipment_status_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/focus_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/glass_card.dart` (app-ui)
- `??` `packages/nightshade_app/lib/screens/dashboard/widgets/guiding_card.dart` (app-ui)
- ... 262 more entries in JSON.

### 9. Tests And Support Tooling

- Bucket ID: `tests-and-support-tooling`
- Count: `64`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/09-tests-and-support-tooling.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt`
- Tracked changes: `14`
- Untracked: `50`
- Deleted: `0`
- Release-critical: `0`
- Intent: Review non-release test files, scripts, package config, and developer tooling separately from product behavior.
- Recommended action: Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

Category mix:

- `package-config`: `2`
- `tests`: `58`
- `tooling`: `4`

Examples:

- ` M` `apps/desktop/pubspec.yaml` (package-config)
- `??` `apps/desktop/test/headless_api/analytics_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auth_middleware_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auth_policy_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/auxiliary_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/backup_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/device_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/equipment_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/filesystem_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/flat_wizard_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/focus_model_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/framing_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/guiding_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/imaging_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/mosaic_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/network_backend_contract_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/planetarium_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/profile_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/response_helpers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/route_metadata_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/safety_monitor_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/scheduler_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/science_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/sequence_management_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/sequencer_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/session_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/suggestion_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/target_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/transient_handlers_test.dart` (tests)
- `??` `apps/desktop/test/headless_api/weather_handlers_test.dart` (tests)
- ... 34 more entries in JSON.

### 10. Out Of Release Scope Review

- Bucket ID: `out-of-release-scope-review`
- Count: `57`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/10-out-of-release-scope-review.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt`
- Tracked changes: `13`
- Untracked: `44`
- Deleted: `0`
- Release-critical: `0`
- Intent: Quarantine scratch reports, research files, goal tracking, and broad miscellaneous edits until they are explicitly accepted or excluded.
- Recommended action: Do not stage into the public release branch without owner review and an explicit reason.

Category mix:

- `docs`: `25`
- `other`: `32`

Examples:

- `??` `.audit_highrisk.txt` (other)
- `??` `.audit_highrisk_debug.txt` (other)
- `??` `.audit_hits.txt` (other)
- `??` `.audit_hits_debug.txt` (other)
- ` M` `.behavioral_audit_hits.txt` (other)
- `??` `.github/workflows/linux-release-build.yml` (other)
- `??` `.ui_consistency_audit.txt` (other)
- `??` `_fw_research/GXUP0006.DAT` (other)
- `??` `_fw_research/GXUP0007.DAT` (other)
- ` M` `docs/api/README.md` (docs)
- ` M` `docs/api/bridge-api.md` (docs)
- ` M` `docs/api/data-models.md` (docs)
- ` M` `docs/api/plugin-api.md` (docs)
- ` M` `docs/api/web-server-api.md` (docs)
- ` M` `docs/features/imaging.md` (docs)
- ` M` `docs/features/sequencing.md` (docs)
- ` M` `docs/getting-started/first-connection.md` (docs)
- ` M` `docs/getting-started/first-image.md` (docs)
- ` M` `docs/getting-started/installation.md` (docs)
- ` M` `docs/index.md` (docs)
- `??` `docs/plugin_sdk/README.md` (docs)
- `??` `docs/plugin_sdk/api_reference.md` (docs)
- `??` `docs/plugin_sdk/best_practices.md` (docs)
- `??` `docs/plugin_sdk/events.md` (docs)
- `??` `docs/plugin_sdk/plugin_types.md` (docs)
- `??` `docs/plugin_sdk/storage.md` (docs)
- `??` `docs/troubleshooting/alpaca.md` (docs)
- `??` `docs/troubleshooting/ascom.md` (docs)
- ` M` `docs/troubleshooting/common-issues.md` (docs)
- `??` `docs/troubleshooting/drivers.md` (docs)
- ... 27 more entries in JSON.

## Release Branch Implication

A clean public release branch still requires each bucket to be staged, excluded, or split into smaller PRs intentionally. The current branch remains `main`, so this plan is evidence for scoping only, not release readiness.
