# Release PR Staged Branch Validation

- Generated at: `2026-06-16T19:58:44.043814Z`
- Matrix: `docs/production-readiness/release-pr-owner-decision-matrix.json`
- Mode: `branch`
- Base: `main`
- Passed: `true`
- Observed paths: `202`
- Issues: `0`
- Warnings: `2`

## Issues

None.

## Warnings

- Generated Only paths are not included in this validation.
- Unplanned paths are present: `docs/production-readiness/public-release-blocker-inputs.json`, `docs/production-readiness/public-release-blocker-inputs.md`, `docs/production-readiness/public-release-checklist-audit.json`, `docs/production-readiness/public-release-checklist-audit.md`, `docs/production-readiness/public-release-completion-audit.json`, `docs/production-readiness/public-release-completion-audit.md`, `docs/production-readiness/public-release-gate.json`, `docs/production-readiness/public-release-gate.md`, `docs/production-readiness/public-release-owner-checklist.json`, `docs/production-readiness/public-release-owner-checklist.md`, `melos.yaml`, `tools/production/hardware_availability_probe.dart`, `tools/production/public_release_blocker_inputs.dart`, `tools/production/public_release_gate.dart`

## Matrix Integrity

- Source split plan: `docs/production-readiness/release-pr-split-plan.json`
- Source split plan exists: `true`
- Source split plan matches matrix: `true`

| Pathspec | Group | Exists | Lines | Matrix paths | Missing | Unexpected | Duplicates |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt` | `must_ship` | `true` | `67` | `67` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt` | `must_ship` | `true` | `33` | `33` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt` | `must_ship` | `true` | `19` | `19` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt` | `must_ship` | `true` | `25` | `25` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt` | `must_ship` | `true` | `27` | `27` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt` | `must_ship` | `true` | `16` | `16` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt` | `binary_evidence` | `true` | `1` | `1` | `0` | `0` | `0` |
| `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt` | `defer_exclude` | `true` | `1` | `1` | `0` | `0` | `0` |

## Decision Group Coverage

| Group | Rule | Status | Paths | Observed | Missing | Forbidden |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| Must Ship | `required_all` | `complete` | `187` | `187` | `0` | `0` |
| Generated Only | `optional_all_or_none` | `not_included` | `0` | `0` | `0` | `0` |
| Binary / Evidence | `optional_all_or_none` | `complete` | `1` | `1` | `0` | `0` |
| Defer / Exclude | `forbidden` | `clean` | `1` | `0` | `1` | `0` |

## Next Stage Commands

These commands are derived from the owner decision matrix pathspecs. Review the pathspec files before running them; cleanup commands only change the staged index.

### Must Ship

- Status: `complete`
- Rule: `required_all`
- Purpose: Required: stage every listed pathspec before the release PR validation can pass.

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt
```

### Binary / Evidence

- Status: `complete`
- Rule: `optional_all_or_none`
- Purpose: Optional: leave this group unstaged, or stage every listed pathspec together.

```powershell
git add --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt
```

### Defer / Exclude

- Status: `clean`
- Rule: `forbidden`
- Purpose: Cleanup: remove these paths from the index if they appear in a staged release branch.

```powershell
git restore --staged --pathspec-from-file=docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt
```

## Observed Paths

- `.github/workflows/linux-release-build.yml`
- `.github/workflows/release.yml`
- `apps/desktop/lib/desktop_app_bootstrap.dart`
- `apps/desktop/lib/headless_api/handlers.dart`
- `apps/desktop/lib/headless_api/handlers/analytics_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/calibration_handlers/dark_library_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/calibration_handlers/defect_map_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/collaboration_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/device_handlers/mount_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/imaging_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/narrator_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/planetarium_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/post_session_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/profile_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/run_watch_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/science_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/sequencer_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/stacking_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/system_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/update_handlers.dart`
- `apps/desktop/lib/headless_api/handlers/weather_handlers.dart`
- `apps/desktop/lib/headless_api/routes.dart`
- `apps/desktop/lib/headless_api/routes/analytics_routes.dart`
- `apps/desktop/lib/headless_api/routes/calibration_routes.dart`
- `apps/desktop/lib/headless_api/routes/imaging_routes.dart`
- `apps/desktop/lib/headless_api/routes/narrator_routes.dart`
- `apps/desktop/lib/headless_api/routes/post_session_routes.dart`
- `apps/desktop/lib/headless_api/routes/stacking_routes.dart`
- `apps/desktop/lib/headless_api/validation.dart`
- `apps/desktop/lib/headless_api_server.dart`
- `apps/desktop/lib/headless_api_server/handler_initialization.dart`
- `apps/desktop/lib/headless_api_server/server_lifecycle.dart`
- `apps/desktop/lib/headless_api_server/websocket_sessions.dart`
- `apps/desktop/lib/main_headless.dart`
- `apps/desktop/linux/CMakeLists.txt`
- `apps/desktop/test/headless_api/auxiliary_handlers_test.dart`
- `apps/desktop/test/headless_api/filesystem_handlers_test.dart`
- `apps/desktop/test/headless_api/mount_status_serialization_test.dart`
- `apps/desktop/test/headless_api/set_location_mirror_test.dart`
- `apps/desktop/test/headless_api/stacking_handlers_test.dart`
- `apps/desktop/test/headless_api/update_handlers_test.dart`
- `docs/design/goldens/surface-run-session-progress.png`
- `docs/headless-secure-setup.md`
- `docs/production-readiness/analyzer-rollup.json`
- `docs/production-readiness/developer-quality-audit.json`
- `docs/production-readiness/developer-quality-audit.md`
- `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json`
- `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json`
- `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json`
- `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json`
- `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json`
- `docs/production-readiness/fail-closed-audit.json`
- `docs/production-readiness/fail-closed-audit.md`
- `docs/production-readiness/headless-api-contract-audit.json`
- `docs/production-readiness/headless-api-contract-audit.md`
- `docs/production-readiness/linux-environment-probe.json`
- `docs/production-readiness/linux-environment-probe.md`
- `docs/production-readiness/linux-release-build-evidence.json`
- `docs/production-readiness/linux-release-package-metadata.json`
- `docs/production-readiness/linux-runtime-smoke.log`
- `docs/production-readiness/public-release-blocker-inputs.json`
- `docs/production-readiness/public-release-blocker-inputs.md`
- `docs/production-readiness/public-release-checklist-audit.json`
- `docs/production-readiness/public-release-checklist-audit.md`
- `docs/production-readiness/public-release-completion-audit.json`
- `docs/production-readiness/public-release-completion-audit.md`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/public-release-external-evidence.md`
- `docs/production-readiness/public-release-gate.json`
- `docs/production-readiness/public-release-gate.md`
- `docs/production-readiness/public-release-owner-checklist.json`
- `docs/production-readiness/public-release-owner-checklist.md`
- `docs/production-readiness/release-pr-drafts/01-binary-and-evidence-artifacts.md`
- `docs/production-readiness/release-pr-drafts/02-release-infra-evidence.md`
- `docs/production-readiness/release-pr-drafts/03-headless-remote-api.md`
- `docs/production-readiness/release-pr-drafts/04-native-driver-bridge.md`
- `docs/production-readiness/release-pr-drafts/05-core-data-model.md`
- `docs/production-readiness/release-pr-drafts/06-desktop-ui-workflows.md`
- `docs/production-readiness/release-pr-drafts/07-tests-and-support-tooling.md`
- `docs/production-readiness/release-pr-drafts/08-out-of-release-scope-review.md`
- `docs/production-readiness/release-pr-lists/01-must-ship.txt`
- `docs/production-readiness/release-pr-lists/02-generated-only.txt`
- `docs/production-readiness/release-pr-lists/03-binary-evidence.txt`
- `docs/production-readiness/release-pr-lists/04-defer-exclude.txt`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.md`
- `docs/production-readiness/release-pr-pathspecs/01-binary-and-evidence-artifacts.txt`
- `docs/production-readiness/release-pr-pathspecs/02-release-infra-evidence.txt`
- `docs/production-readiness/release-pr-pathspecs/03-headless-remote-api.txt`
- `docs/production-readiness/release-pr-pathspecs/04-native-driver-bridge.txt`
- `docs/production-readiness/release-pr-pathspecs/05-core-data-model.txt`
- `docs/production-readiness/release-pr-pathspecs/06-desktop-ui-workflows.txt`
- `docs/production-readiness/release-pr-pathspecs/07-tests-and-support-tooling.txt`
- `docs/production-readiness/release-pr-pathspecs/08-out-of-release-scope-review.txt`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-split-plan.md`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-staged-branch-validation.md`
- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-staging-audit.md`
- `docs/supported-hardware-by-platform.md`
- `docs/troubleshooting/indi.md`
- `melos.yaml`
- `native/nightshade_native/alpaca/src/client.rs`
- `native/nightshade_native/alpaca/src/discovery.rs`
- `native/nightshade_native/bridge/src/api/discovery.rs`
- `native/nightshade_native/bridge/src/device_id.rs`
- `native/nightshade_native/bridge/src/device_manager/ops/camera.rs`
- `native/nightshade_native/bridge/src/dispatch/indi.rs`
- `native/nightshade_native/imaging/build.rs`
- `native/nightshade_native/indi/src/client.rs`
- `native/nightshade_native/native/src/vendor/atik.rs`
- `native/nightshade_native/native/src/vendor/fli.rs`
- `native/nightshade_native/native/src/vendor/gphoto2.rs`
- `native/nightshade_native/native/src/vendor/moravian.rs`
- `native/nightshade_native/native/src/vendor/player_one.rs`
- `native/nightshade_native/native/src/vendor/qhy.rs`
- `native/nightshade_native/native/src/vendor/sdk_loader.rs`
- ... 82 more paths omitted.
