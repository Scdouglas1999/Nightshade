# Release PR Split Plan

- Source audit: `docs/production-readiness/release-staging-audit.json`
- Branch: `release/hardening-audit-2026-06-16`
- HEAD: `bd4b2544`
- Entries assigned to proposed review buckets: `189`
- Non-empty buckets: `8`
- Untracked release-critical entries: `0`
- Pathspec directory: `docs/production-readiness/release-pr-pathspecs`
- Draft PR descriptions: `docs/production-readiness/release-pr-drafts`
- Release decision lists: `docs/production-readiness/release-pr-lists`

This is a planning artifact. It does not stage files, create a branch, create a PR, or make the public release gate pass.

## Bucket Summary

| Suggested order | Bucket | Count | Untracked | Release-critical | Generated | Binary |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | Binary And Evidence Artifacts | 1 | 0 | 0 | 0 | 1 |
| 2 | Release Infrastructure And Evidence | 67 | 0 | 67 | 0 | 0 |
| 3 | Headless Remote API And Dashboard | 33 | 0 | 30 | 0 | 0 |
| 4 | Native Driver And Bridge Source | 19 | 0 | 19 | 0 | 0 |
| 5 | Core Data Model And Services | 25 | 0 | 25 | 0 | 0 |
| 6 | Desktop UI And Workflow Packages | 27 | 0 | 22 | 0 | 0 |
| 7 | Tests And Support Tooling | 16 | 0 | 0 | 0 | 0 |
| 8 | Out Of Release Scope Review | 1 | 1 | 0 | 0 | 0 |

## Release Decision Lists

The lists below are mutually exclusive. Generated and binary/evidence paths are separated before release-critical source/docs paths so reviewers can stage those concern areas independently.

| List | Count | File | Description |
| --- | ---: | --- | --- |
| Must Ship | 163 | `docs/production-readiness/release-pr-lists/01-must-ship.txt` | Release-critical source, docs, and tooling paths that are not generated outputs or binary/evidence artifacts. |
| Generated Only | 0 | `docs/production-readiness/release-pr-lists/02-generated-only.txt` | Generated files that should be reviewed against their source changes and generator commands. |
| Binary And Evidence | 1 | `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` | Binary payloads, screenshots, APKs, DLLs, and other evidence artifacts that need explicit artifact review. |
| Defer Or Exclude | 25 | `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` | Non-release-critical paths that need owner review before they are staged into a public release branch. |

## Proposed Review Buckets

### 1. Binary And Evidence Artifacts

- Bucket ID: `binary-and-evidence-artifacts`
- Count: `1`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/01-binary-and-evidence-artifacts.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`
- Tracked changes: `1`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `0`
- Intent: Review DLLs, APKs, screenshots, databases, and other binary artifacts outside normal source diffs.
- Recommended action: Keep release payload binaries and smoke evidence in a deliberate artifact review; exclude scratch screenshots and research blobs from the release PR.

Category mix:

- `binary-native-artifact`: `1`

Examples:

- `M ` `docs/design/goldens/surface-run-session-progress.png` (binary-native-artifact)

### 2. Release Infrastructure And Evidence

- Bucket ID: `release-infra-evidence`
- Count: `67`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/02-release-infra-evidence.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`
- Tracked changes: `67`
- Untracked: `0`
- Deleted: `1`
- Release-critical: `67`
- Intent: Keep release gates, production audit tools, public readiness docs, and operational docs together.
- Recommended action: Stage audit tooling and evidence docs as the release-readiness PR only after confirming each artifact is current and reproducible.

Category mix:

- `docs`: `3`
- `other`: `15`
- `release-evidence-docs`: `47`
- `release-tooling`: `2`

Examples:

- `M ` `.github/workflows/linux-release-build.yml` (other)
- `M ` `.github/workflows/release.yml` (other)
- `M ` `apps/desktop/linux/CMakeLists.txt` (other)
- `M ` `docs/headless-secure-setup.md` (docs)
- `A ` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- `A ` `docs/production-readiness/developer-quality-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/developer-quality-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json` (release-evidence-docs)
- `A ` `docs/production-readiness/fail-closed-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/fail-closed-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/headless-api-contract-audit.json` (release-evidence-docs)
- `A ` `docs/production-readiness/headless-api-contract-audit.md` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-environment-probe.json` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-environment-probe.md` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-release-build-evidence.json` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-release-package-metadata.json` (release-evidence-docs)
- `A ` `docs/production-readiness/linux-runtime-smoke.log` (release-evidence-docs)
- `A ` `docs/production-readiness/public-release-external-evidence.json` (release-evidence-docs)
- `A ` `docs/production-readiness/public-release-external-evidence.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/01-binary-and-evidence-artifacts.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/02-release-infra-evidence.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/03-headless-remote-api.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/04-native-driver-bridge.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/05-core-data-model.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/06-desktop-ui-workflows.md` (release-evidence-docs)
- `A ` `docs/production-readiness/release-pr-drafts/07-tests-and-support-tooling.md` (release-evidence-docs)
- ... 37 more entries in JSON.

### 3. Headless Remote API And Dashboard

- Bucket ID: `headless-remote-api`
- Count: `33`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/03-headless-remote-api.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`
- Tracked changes: `33`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `30`
- Intent: Review headless server routes, auth policy, dashboard assets, LAN behavior, and WebSocket changes as one API surface.
- Recommended action: Pair this bucket with route contract tests, dashboard smoke logs, auth/LAN evidence, and reconnect evidence.

Category mix:

- `headless-remote`: `33`

Examples:

- `M ` `apps/desktop/lib/headless_api/handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/calibration_handlers/dark_library_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/calibration_handlers/defect_map_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/collaboration_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/device_handlers/mount_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/narrator_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/planetarium_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/post_session_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/profile_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/run_watch_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/science_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/sequencer_handlers.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/handlers/stacking_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/system_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/update_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/handlers/weather_handlers.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/routes.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/routes/analytics_routes.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/routes/calibration_routes.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/routes/imaging_routes.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/routes/narrator_routes.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/routes/post_session_routes.dart` (headless-remote)
- `A ` `apps/desktop/lib/headless_api/routes/stacking_routes.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api/validation.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api_server.dart` (headless-remote)
- `M ` `apps/desktop/lib/headless_api_server/handler_initialization.dart` (headless-remote)
- ... 3 more entries in JSON.

### 4. Native Driver And Bridge Source

- Bucket ID: `native-driver-bridge`
- Count: `19`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/04-native-driver-bridge.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`
- Tracked changes: `19`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `19`
- Intent: Review Rust native code, driver integrations, Flutter Rust Bridge source, and bridge package API changes together.
- Recommended action: Keep source changes apart from compiled DLLs; require platform build evidence and driver capability notes before release staging.

Category mix:

- `bridge`: `1`
- `native-rust`: `18`

Examples:

- `M ` `native/nightshade_native/alpaca/src/client.rs` (native-rust)
- `M ` `native/nightshade_native/alpaca/src/discovery.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/api/discovery.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/device_id.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/device_manager/ops/camera.rs` (native-rust)
- `M ` `native/nightshade_native/bridge/src/dispatch/indi.rs` (native-rust)
- `M ` `native/nightshade_native/imaging/build.rs` (native-rust)
- `M ` `native/nightshade_native/indi/src/client.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/atik.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/fli.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/gphoto2.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/moravian.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/player_one.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/qhy.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/sdk_loader.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/svbony.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/touptek.rs` (native-rust)
- `M ` `native/nightshade_native/native/src/vendor/zwo.rs` (native-rust)
- `M ` `packages/nightshade_bridge/lib/src/bridge_stub/connection_operations.dart` (bridge)

### 5. Core Data Model And Services

- Bucket ID: `core-data-model`
- Count: `25`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/05-core-data-model.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`
- Tracked changes: `25`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `25`
- Intent: Review database, model, provider, backend, migration, and shared service changes as a data/API compatibility set.
- Recommended action: Stage with focused tests and a real older-profile migration artifact; generated DB/model files stay in the generated-files bucket.

Category mix:

- `core`: `25`

Examples:

- `M ` `packages/nightshade_core/lib/src/backend/ffi_backend/bridge_model_mappers.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/connection_lifecycle.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/http_transport.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/imaging_profile_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/planning_accessory_operations.dart` (core)
- `A ` `packages/nightshade_core/lib/src/backend/network_backend/post_session_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/remote_calibration_catalog_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/remote_live_view_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/backend/network_backend/session_science_operations.dart` (core)
- `A ` `packages/nightshade_core/lib/src/backend/network_backend/stacking_operations.dart` (core)
- `M ` `packages/nightshade_core/lib/src/database/database/connection.dart` (core)
- `M ` `packages/nightshade_core/lib/src/models/calibration/calibration_library_models.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/defect_map_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/live_stacking_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/narrator_provider.dart` (core)
- `M ` `packages/nightshade_core/lib/src/providers/sequence/sequence_executor.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration/defect_map_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration_library_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/calibration_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/device_service/connections.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/live_stacking_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/post_session_seam.dart` (core)
- `M ` `packages/nightshade_core/lib/src/services/switch_channel_service.dart` (core)
- `M ` `packages/nightshade_core/lib/src/utils/device_id.dart` (core)

### 6. Desktop UI And Workflow Packages

- Bucket ID: `desktop-ui-workflows`
- Count: `27`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/06-desktop-ui-workflows.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`
- Tracked changes: `27`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `22`
- Intent: Review app UI, shared UI system, planetarium, plugin, updater, WebRTC, and desktop workflow changes together or split by screen if too large.
- Recommended action: Use UI consistency audit results and focused screenshot/smoke evidence before moving these paths into a release PR.

Category mix:

- `app-ui`: `22`
- `other`: `1`
- `remote-protocol`: `3`
- `updater`: `1`

Examples:

- `M ` `apps/desktop/lib/desktop_app_bootstrap.dart` (other)
- `M ` `packages/nightshade_app/lib/screens/analytics/widgets/photometric_calibration_wizard/star_matching.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/analytics/widgets/project_tracking_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/equipment_screen/progress_dashboard.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/actions_and_telemetry.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/command_handlers.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/equipment/widgets/connected_device_card/dialogs_and_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/equipment/widgets/switch_control_card.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/imaging_screen/imaging_screen_actions.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/calibration_section.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/rotator_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/imaging/widgets/stacking_panel.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/sequencer/widgets/smart_night_dialog.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/settings_catalog.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/calibration_library_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/captured_images_settings.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/connection_settings.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/file_path_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/focus_model_settings.dart` (app-ui)
- `M ` `packages/nightshade_app/lib/screens/settings/widgets/log_viewer.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/rig_catalog_settings.dart` (app-ui)
- `A ` `packages/nightshade_app/lib/screens/settings/widgets/update_settings.dart` (app-ui)
- `M ` `packages/nightshade_remote_protocol/lib/src/discovery.dart` (remote-protocol)
- `M ` `packages/nightshade_remote_protocol/lib/src/enhanced_discovery.dart` (remote-protocol)
- `M ` `packages/nightshade_remote_protocol/test/enhanced_discovery_test.dart` (remote-protocol)
- `M ` `packages/nightshade_updater/test/lan_push_test.dart` (updater)

### 7. Tests And Support Tooling

- Bucket ID: `tests-and-support-tooling`
- Count: `16`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/07-tests-and-support-tooling.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`
- Tracked changes: `16`
- Untracked: `0`
- Deleted: `0`
- Release-critical: `0`
- Intent: Review non-release test files, scripts, package config, and developer tooling separately from product behavior.
- Recommended action: Stage only support changes needed to verify the release; defer unrelated audit scratch or developer-only helpers.

Category mix:

- `tests`: `14`
- `tooling`: `2`

Examples:

- `M ` `apps/desktop/test/headless_api/auxiliary_handlers_test.dart` (tests)
- `M ` `apps/desktop/test/headless_api/filesystem_handlers_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/mount_status_serialization_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/set_location_mirror_test.dart` (tests)
- `A ` `apps/desktop/test/headless_api/stacking_handlers_test.dart` (tests)
- `M ` `apps/desktop/test/headless_api/update_handlers_test.dart` (tests)
- `M ` `packages/nightshade_app/test/screens/imaging/widgets/rotator_panel_angle_range_test.dart` (tests)
- `A ` `packages/nightshade_core/test/backend/network_backend_narrator_test.dart` (tests)
- `A ` `packages/nightshade_core/test/backend/network_backend_switch_test.dart` (tests)
- `M ` `packages/nightshade_core/test/backend/network_backend_websocket_test.dart` (tests)
- `A ` `packages/nightshade_core/test/database/database_connection_test.dart` (tests)
- `A ` `packages/nightshade_core/test/live_appliance_realtime_probe.dart` (tests)
- `M ` `packages/nightshade_core/test/providers/sequence/sequence_executor_live_stacking_autofeed_test.dart` (tests)
- `M ` `packages/nightshade_core/test/utils/device_id_test.dart` (tests)
- `M ` `scripts/dev.sh` (tooling)
- `M ` `scripts/docker_build_linux.sh` (tooling)

### 8. Out Of Release Scope Review

- Bucket ID: `out-of-release-scope-review`
- Count: `1`
- Pathspec file: `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`
- Draft PR description: `docs/production-readiness/release-pr-drafts/08-out-of-release-scope-review.md`
- Stage command: `git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`
- Tracked changes: `0`
- Untracked: `1`
- Deleted: `0`
- Release-critical: `0`
- Intent: Quarantine scratch reports, research files, goal tracking, and broad miscellaneous edits until they are explicitly accepted or excluded.
- Recommended action: Do not stage into the public release branch without owner review and an explicit reason.

Category mix:

- `other`: `1`

Examples:

- `??` `.agents/skills/deslop/SKILL.md` (other)

## Release Branch Implication

A clean public release branch still requires each bucket to be staged, excluded, or split into smaller PRs intentionally. The current branch remains `release/hardening-audit-2026-06-16`, so this plan is evidence for scoping only, not release readiness.
