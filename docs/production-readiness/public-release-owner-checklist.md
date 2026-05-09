# Public Release Owner Checklist

- Source audit: `docs/production-readiness/public-release-completion-audit.json`
- Completion audit generated at: `2026-05-06T14:38:25.105301Z`
- Decision: `NOT_ACHIEVED`
- Gate decision: `NOT_READY`
- Completion detail: One or more P0 requirements remain blocked or weakly verified.
- Ready: `false`
- Items: `7`
- Complete: `0`
- Blocked or incomplete: `7`

This owner checklist is generated from structured completion-audit fields. Edit the underlying evidence, not this generated file.

## Source Artifacts

| Artifact | Exists | Generated | Decision | Count | Blockers |
| --- | ---: | --- | --- | ---: | ---: |
| `goal.txt` | `true` | `2026-05-05T00:20:03.000Z` | `` | `` | `` |
| `docs/production-readiness/public-release-gate.json` | `true` | `2026-05-06T14:38:13.927557Z` | `NOT_READY` | `18` | `7` |
| `docs/production-readiness/public-release-blocker-inputs.json` | `true` | `2026-05-06T01:16:56.433074Z` | `NOT_READY` | `` | `7` |
| `docs/production-readiness/public-release-external-evidence.json` | `true` | `2026-05-06T11:18:47.059351Z` | `ready=false` | `0` | `` |
| `docs/production-readiness/release-staging-audit.json` | `true` | `2026-05-06T09:42:35.600502Z` | `` | `913` | `` |
| `docs/production-readiness/release-pr-split-plan.json` | `true` | `2026-05-06T09:42:36.905333Z` | `` | `913` | `` |
| `docs/production-readiness/release-pr-owner-decision-matrix.json` | `true` | `2026-05-06T10:22:53.024152Z` | `` | `913` | `` |
| `docs/production-readiness/release-pr-staged-branch-validation.json` | `true` | `2026-05-06T10:23:09.445212Z` | `` | `` | `` |
| `docs/production-readiness/public-release-checklist-audit.json` | `true` | `2026-05-06T01:17:07.040302Z` | `` | `` | `` |

## Goal Sections Observed

- `P0 Before Public Release`
- `UI Consistency`
- `Headless And Remote`
- `Platform Parity`
- `Hardware Workflows`
- `Sequencer`
- `Imaging And Processing`
- `Math And Astronomy`
- `Competitor-Parity Features`
- `Performance And Code Quality`
- `Docs And Release UX`

## Summary

| Status | Requirement | Gap |
| --- | --- | --- |
| `blocked` | Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable. | Current branch=main; entryCount=913; untrackedReleaseCritical=336; stagedBranchValidationPassed=false. |
| `in_progress` | Split generated/binary/native changes from Dart/UI changes where possible. | Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=10; entryCount=913; ownerMatrixPaths=913; stagedBranchValidationPassed=false. |
| `blocked` | Do a Linux release build on an actual Linux environment, not inferred from Windows. | See required input. |
| `blocked` | Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices. | See required input. |
| `blocked` | Verify upgrade/migration from an older Nightshade profile/database. | See required input. |
| `incomplete` | Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together. | See required input. |
| `blocked` | Produce a release checklist with known unsupported-by-platform items clearly documented. | Checklist audit unchecked=284; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=0/5. |

## Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable.

- ID: `clean_release_branch_pr`
- Status: `blocked`
- Verification: Gate check `release_staging` requires a non-main clean branch with no untracked release-critical entries.
- Gap: Current branch=main; entryCount=913; untrackedReleaseCritical=336; stagedBranchValidationPassed=false.

Required input:

- Owner decision on must ship, generated only, binary/evidence, and defer/exclude bucket lists, then a clean non-main release branch/PR validated against that matrix.
Rerun commands:

- `dart run melos run audit:release-staging --no-select`
- `dart run melos run audit:release-pr-plan --no-select`
- `dart run melos run audit:release-pr-owner-matrix --no-select`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Work is on a non-main release branch.
- `dart run melos run audit:release-staging --no-select` reports entryCount=0 and untrackedReleaseCriticalCount=0 for the final PR workspace, or the final PR contains only intentionally staged release files with exclusions documented.
- The owner matrix lists every split-plan bucket under must_ship, generated_only, binary_evidence, or defer_exclude.
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index` or the branch-mode equivalent passes before PR creation.
- The PR description links the staged bucket pathspecs, uses the draft description for each bucket, and explains any excluded bucket.
Expected evidence:

- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.md`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`
- `GitHub PR URL or local branch/review record`
Current evidence references:

- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`

## Split generated/binary/native changes from Dart/UI changes where possible.

- ID: `split_generated_binary_native`
- Status: `in_progress`
- Verification: Split plan assigns dirty entries into generated, binary/evidence, native/bridge, core, UI, and other buckets with pathspec files; owner matrix separates must_ship, generated_only, binary_evidence, and defer_exclude; validator checks the staged index or branch diff against that matrix.
- Gap: Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=10; entryCount=913; ownerMatrixPaths=913; stagedBranchValidationPassed=false.

Required input:

- Owner decision on must ship, generated only, binary/evidence, and defer/exclude bucket lists, then a clean non-main release branch/PR validated against that matrix.
Rerun commands:

- `dart run melos run audit:release-staging --no-select`
- `dart run melos run audit:release-pr-plan --no-select`
- `dart run melos run audit:release-pr-owner-matrix --no-select`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Work is on a non-main release branch.
- `dart run melos run audit:release-staging --no-select` reports entryCount=0 and untrackedReleaseCriticalCount=0 for the final PR workspace, or the final PR contains only intentionally staged release files with exclusions documented.
- The owner matrix lists every split-plan bucket under must_ship, generated_only, binary_evidence, or defer_exclude.
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index` or the branch-mode equivalent passes before PR creation.
- The PR description links the staged bucket pathspecs, uses the draft description for each bucket, and explains any excluded bucket.
Expected evidence:

- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.md`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`
- `GitHub PR URL or local branch/review record`
Current evidence references:

- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`

## Do a Linux release build on an actual Linux environment, not inferred from Windows.

- ID: `linux_release_build`
- Status: `blocked`
- Verification: Gate requires the external evidence validator to accept Linux build/package evidence.
- Gap: See required input.

Required input:

- A working Linux build environment, either repaired WSL Ubuntu, Docker Desktop Linux engine, or another Linux host/CI runner.
Rerun commands:

- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:linux-environment --no-select`
- `dart run melos run build:desktop:linux --no-select`
- `dart run melos run audit:linux-release-package-metadata --no-select`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- `dart run melos run build:desktop:linux --no-select` succeeds on Linux.
- Linux package/runtime artifact is recorded with path, size, hash, and native library/permission notes from the package metadata generator or CI workflow.
- Linux-launched headless/dashboard smoke evidence exists from that Linux artifact.
Expected evidence:

- `docs/production-readiness/linux-release-build-evidence.json`
- `docs/production-readiness/linux-release-package-metadata.json`
- `docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/linux-environment-probe.json`
- `.github/workflows/linux-release-build.yml workflow run and uploaded artifact metadata`
- `Linux build log`
- `Linux package artifact path/hash`
- `Linux runtime/headless smoke log`
Current evidence references:

- `docs/production-readiness/linux-environment-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/linux-release-build-evidence.json`

## Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices.

- ID: `full_hardware_smoke`
- Status: `blocked`
- Verification: Gate requires validated external full hardware/control smoke evidence covering all required device classes.
- Gap: See required input.

Required input:

- A rig, simulator-backed environment, or remote host that exposes camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety monitor classes, plus permission to run safe control commands.
Rerun commands:

- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:hardware-availability:windows --no-select`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Every required device class is discoverable as real or simulator-backed for the smoke environment.
- Connect/disconnect is exercised for each required class.
- Safe read/status command is exercised for each required class.
- Safe control command is exercised where applicable, such as camera short exposure, focuser small move, filter position query/change, rotator angle query/change, guider status, dome status/open-close or simulator equivalent, weather read, and safety state read.
- The smoke log records device IDs, driver types, command results, and any intentionally skipped unsafe action.
Expected evidence:

- `docs/production-readiness/full-hardware-control-smoke-evidence.json`
- `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/hardware-availability-probe.json`
- `Full hardware/control smoke log with command results`
- `Screenshots or exported dashboard/device-state evidence if manually driven`
Current evidence references:

- `docs/production-readiness/hardware-availability-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/full-hardware-control-smoke-evidence.json`

## Verify upgrade/migration from an older Nightshade profile/database.

- ID: `older_profile_migration`
- Status: `blocked`
- Verification: Manual migration probe must run against an older real database/profile and report migrationVerified=true. Synthetic regression tests cover old-schema/profile fixtures but do not replace the real older-profile artifact.
- Gap: See required input.

Required input:

- An older real Nightshade SQLite database/profile artifact that can be copied and migrated by the probe.
Rerun commands:

- `cd packages/nightshade_core && flutter test test/services/database_migration_test.dart`
- `$env:NIGHTSHADE_OLD_DATABASE="<path-to-old-nightshade.sqlite>"`
- `dart run melos run audit:manual-migration --no-select`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Probe runs against a temporary copy of an older real database/profile.
- `artifactProvided=true` and `migrationVerified=true` in `manual-migration-probe.json`.
- Report records source path, source size, source SHA256, original user_version, final user_version, current table set, and required default settings.
- Synthetic old-schema/profile migration regression tests pass without using real user data.
Expected evidence:

- `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart`
- `packages/nightshade_core/test/services/database_migration_test.dart`
- `docs/production-readiness/manual-migration-probe.json`
- `docs/production-readiness/manual-migration-probe.md`
- `Path or secure reference to the source old database artifact`
Current evidence references:

- `docs/production-readiness/manual-migration-probe.json`
- `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart`
- `packages/nightshade_core/test/services/database_migration_test.dart`

## Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together.

- ID: `integrated_remote_headless`
- Status: `incomplete`
- Verification: Emulator/mobile and reconnect evidence pass, but second physical LAN/firewall and real remote-control action evidence are still required.
- Gap: See required input.

Required input:

- A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it. Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices.
Rerun commands:

- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run smoke:headless-lan:windows`
- `dart run melos run audit:public-release-gate --no-select`
- `dart run melos run audit:hardware-availability:windows --no-select`
Acceptance criteria:

- Packaged Windows headless server is reached from the second device over the LAN IP, not localhost or emulator alias.
- Dashboard loads with HTML/CSS/JS assets.
- Authenticated token flow succeeds and missing/wrong token fails.
- WebSocket connects and reconnect behavior is observed or logged.
- Evidence records server LAN URL, client device type, network path, timestamp, and screenshots/logs.
- Remote client sends at least one safe command per applicable device class.
- Server logs include request IDs, client key/token scope, action, route, and completion status for high-risk commands.
- Device state after each command is read back and recorded.
- Unsafe real-world commands are either performed in simulator mode or explicitly skipped with a safety reason.
Expected evidence:

- `docs/production-readiness/second-device-lan-firewall-smoke-evidence.json`
- `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `Second-device browser screenshot or mobile screenshot`
- `Server log showing second-device client IP`
- `Manual smoke notes with firewall/router path`
- `docs/production-readiness/public-release-audit-report.md update`
- `docs/production-readiness/real-remote-control-actions-evidence.json`
- `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json`
- `Remote-control smoke log with command/result pairs`
- `Dashboard/mobile screenshots showing connected state and command results`
- `Server audit log excerpt for high-risk commands`
Current evidence references:

- `docs/production-readiness/android-emulator-remote-smoke-log.txt, docs/production-readiness/android-emulator-remote-smoke.png, docs/production-readiness/mobile-remote-window-connected.xml`
- `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/public-release-audit-report.md`
- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/hardware-availability-probe.json`

## Produce a release checklist with known unsupported-by-platform items clearly documented.

- ID: `release_checklist_known_unsupported`
- Status: `blocked`
- Verification: Final checklist gate requires checklist audit evidence with zero unchecked items, zero checked-without-evidence items, known limitations/support docs references, and validated final sign-off evidence.
- Gap: Checklist audit unchecked=284; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=0/5.

Required input:

- Reviewer sign-off evidence for every remaining checklist item, or explicit release-scope removal for items that cannot be satisfied.
Rerun commands:

- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:public-release-checklist --no-select`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Every completed checklist item has evidence notes.
- Every unchecked release-blocking item is resolved, hidden, or removed from scope.
- Known unsupported-by-platform items are referenced in the known limitations and supported hardware docs.
- Final ship/no-ship decision records date, reviewer, commit/hash, and known limitations.
- `audit:public-release-gate` reports `Decision: READY`.
Expected evidence:

- `docs/production-readiness/final-release-signoff-evidence.json`
- `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/public-release-checklist-audit.json`
- `docs/production-readiness/public-release-gate.json`
- `Final release decision record`
Current evidence references:

- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/public-release-checklist-audit.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/known-limitations.md`
- `docs/supported-hardware-by-platform.md`

