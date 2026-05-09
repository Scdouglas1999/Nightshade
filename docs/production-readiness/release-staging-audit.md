# Release Staging Audit

- Branch: `main`
- HEAD: `bbdee9b`
- Total changed/untracked entries: `913`
- Tracked modified/added/deleted entries: `429`
- Untracked entries: `484`
- Deleted entries: `2`
- Generated entries: `35`
- Binary/evidence/native artifact entries: `31`
- Untracked release-critical entries: `336`

This is a scoping report only. It does not make the worktree clean and does not prove a release branch or PR has been created.

## Category Summary

| Category | Count | Untracked |
| --- | ---: | ---: |
| app-ui | 204 | 107 |
| binary-native-artifact | 27 | 25 |
| bridge | 5 | 0 |
| core | 127 | 45 |
| docs | 30 | 18 |
| generated | 35 | 4 |
| headless-remote | 34 | 5 |
| mobile | 9 | 0 |
| native-rust | 95 | 13 |
| other | 37 | 32 |
| package-config | 3 | 0 |
| planetarium | 29 | 12 |
| plugins | 11 | 3 |
| release-evidence-binary | 4 | 4 |
| release-evidence-docs | 98 | 97 |
| release-tooling | 59 | 56 |
| tests | 58 | 50 |
| tooling | 4 | 0 |
| ui-system | 18 | 2 |
| updater | 10 | 3 |
| webrtc | 16 | 8 |

## Required Split Before PR

- Review generated files separately from human-authored source.
- Review binary/native artifacts separately from source diffs.
- Stage release evidence docs and production tools intentionally; many are untracked.
- Do not cut a public tag from this worktree until untracked release-critical entries are either staged or explicitly excluded.


## Untracked Release-Critical Entries

- `??` `apps/desktop/lib/headless_api/auth_policy.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/filesystem_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/handlers/science_handlers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/response_helpers.dart` (headless-remote)
- `??` `apps/desktop/lib/headless_api/route_metadata.dart` (headless-remote)
- `??` `docs/headless-secure-setup.md` (docs)
- `??` `docs/known-limitations.md` (docs)
- `??` `docs/migration-backup-restore.md` (docs)
- `??` `docs/production-readiness/analyzer-rollup.json` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-launch-smoke.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-smoke-latest.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke-log.txt` (release-evidence-docs)
- `??` `docs/production-readiness/android-emulator-remote-smoke-start.png` (release-evidence-binary)
- `??` `docs/production-readiness/android-emulator-remote-smoke.png` (release-evidence-binary)
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
- `??` `docs/production-readiness/linux-release-ci-recipe.md` (release-evidence-docs)
- `??` `docs/production-readiness/linux-release-workflow-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/linux-release-workflow-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/manual-migration-probe.json` (release-evidence-docs)
- `??` `docs/production-readiness/manual-migration-probe.md` (release-evidence-docs)
- `??` `docs/production-readiness/migration-regression-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/migration-regression-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-connected-latest.xml` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-connected.xml` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-initial.xml` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-manual-latest.xml` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-manual.xml` (release-evidence-docs)
- `??` `docs/production-readiness/mobile-remote-window-start.xml` (release-evidence-docs)
- `??` `docs/production-readiness/oversized-file-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/oversized-file-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/platform-capability-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/platform-capability-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-audit-report.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-blocker-inputs.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-blocker-inputs.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-checklist-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-checklist-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-completion-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-completion-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-external-evidence.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-external-evidence.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-gate.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-gate.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-master-checklist.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-owner-checklist.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-owner-checklist.md` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-self-tests.json` (release-evidence-docs)
- `??` `docs/production-readiness/public-release-self-tests.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-docs-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/release-docs-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/01-generated-files.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/02-binary-and-evidence-artifacts.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/03-release-infra-evidence.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/04-headless-remote-api.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/05-mobile-remote-client.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/06-native-driver-bridge.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/07-core-data-model.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/08-desktop-ui-workflows.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/09-tests-and-support-tooling.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-drafts/10-out-of-release-scope-review.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-lists/01-must-ship.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-lists/02-generated-only.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-lists/03-binary-evidence.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-lists/04-defer-exclude.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-owner-decision-matrix.json` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-owner-decision-matrix.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/01-generated-files.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/02-binary-and-evidence-artifacts.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/03-release-infra-evidence.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/04-headless-remote-api.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/05-mobile-remote-client.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/06-native-driver-bridge.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/07-core-data-model.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/08-desktop-ui-workflows.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/09-tests-and-support-tooling.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-pathspecs/10-out-of-release-scope-review.txt` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-split-plan.json` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-split-plan.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-staged-branch-validation.json` (release-evidence-docs)
- `??` `docs/production-readiness/release-pr-staged-branch-validation.md` (release-evidence-docs)
- `??` `docs/production-readiness/release-staging-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/release-staging-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/ui-consistency-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/ui-consistency-audit.md` (release-evidence-docs)
- `??` `docs/production-readiness/windows-bundle-audit.json` (release-evidence-docs)
- `??` `docs/production-readiness/windows-bundle-audit.md` (release-evidence-docs)
- `??` `docs/release-notes-template.md` (docs)
- `??` `docs/supported-hardware-by-platform.md` (docs)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_rotator.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_safetymonitor.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/ascom_wrapper_weather.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/builtin_guider.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/filter_matching.rs` (native-rust)
- `??` `native/nightshade_native/bridge/src/stacking_api.rs` (native-rust)
- `??` `native/nightshade_native/imaging/src/calibration.rs` (native-rust)
- `??` `native/nightshade_native/imaging/src/libraw_shim.c` (native-rust)
- `??` `native/nightshade_native/imaging/src/stacking.rs` (native-rust)
- ... 216 more entries omitted.

## Binary / Evidence Artifact Entries

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
- `??` `report/web-dashboard-hardening.png` (binary-native-artifact)

## Generated Entries

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
- ` M` `packages/nightshade_ui/pubspec.lock` (generated)
- ` M` `packages/nightshade_updater/lib/src/models/update_manifest.freezed.dart` (generated)
- ` M` `packages/nightshade_updater/lib/src/models/update_manifest.g.dart` (generated)
- ` M` `packages/nightshade_updater/pubspec.lock` (generated)
- ` M` `packages/nightshade_webrtc/pubspec.lock` (generated)
