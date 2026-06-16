# Public Release Completion Audit

- Objective source: `goal.txt`
- Objective summary: Prepare Nightshade for public release with direct evidence for the P0 release gates in goal.txt.
- Decision: `NOT_ACHIEVED`
- Gate decision: `NOT_READY`
- Completion detail: One or more P0 requirements remain blocked or weakly verified.
- Complete P0 checks: `3`
- Blocked/incomplete P0 checks: `4`

This audit maps each P0 public-release requirement from `goal.txt` to concrete evidence. Proxy signals are not treated as completion when direct evidence is missing.

## Source Artifacts

| Artifact | Generated | Decision | Count |
| --- | --- | --- | --- |
| `goal.txt` | `unknown` | `` | `` |
| `docs/production-readiness/public-release-gate.json` | `2026-06-16T19:55:32.483020Z` | `NOT_READY` | `20` |
| `docs/production-readiness/public-release-blocker-inputs.json` | `2026-06-16T19:55:36.015473Z` | `NOT_READY` | `` |
| `docs/production-readiness/public-release-external-evidence.json` | `2026-06-16T19:55:28.086493Z` | `ready=false` | `1` |
| `docs/production-readiness/release-staging-audit.json` | `2026-06-16T19:36:20.097609Z` | `` | `0` |
| `docs/production-readiness/release-pr-split-plan.json` | `2026-06-16T19:35:32.397361Z` | `` | `189` |
| `docs/production-readiness/release-pr-owner-decision-matrix.json` | `2026-06-16T19:35:32.479571Z` | `` | `189` |
| `docs/production-readiness/release-pr-staged-branch-validation.json` | `2026-06-16T19:43:31.653388Z` | `` | `` |
| `docs/production-readiness/public-release-checklist-audit.json` | `2026-06-16T19:39:23.130589Z` | `` | `` |

## Prompt-To-Artifact Checklist

| Status | Requirement | Evidence | Gap |
| --- | --- | --- | --- |
| complete | Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable. | docs/production-readiness/release-staging-audit.json; docs/production-readiness/release-pr-split-plan.json; docs/production-readiness/release-pr-staged-branch-validation.json; docs/production-readiness/release-pr-owner-decision-matrix.json; docs/production-readiness/release-pr-pathspecs/*.txt | Current branch=release/hardening-audit-2026-06-16; entryCount=0; untrackedReleaseCritical=0; stagedBranchValidationPassed=true. No blocker-input record found. |
| complete | Split generated/binary/native changes from Dart/UI changes where possible. | docs/production-readiness/release-pr-split-plan.json; docs/production-readiness/release-pr-owner-decision-matrix.json; docs/production-readiness/release-pr-staged-branch-validation.json; docs/production-readiness/release-pr-pathspecs/*.txt | Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=8; entryCount=189; ownerMatrixPaths=189; stagedBranchValidationPassed=true. |
| complete | Do a Linux release build on an actual Linux environment, not inferred from Windows. | docs/production-readiness/linux-environment-probe.json; docs/production-readiness/public-release-external-evidence.json; docs/production-readiness/linux-release-build-evidence.json | No blocker-input record found. |
| blocked | Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices. | docs/production-readiness/hardware-availability-probe.json; docs/production-readiness/public-release-external-evidence.json; docs/production-readiness/full-hardware-control-smoke-evidence.json | Required input: A rig, simulator-backed environment, or remote host that exposes camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety monitor classes, plus permission to run safe control commands. |
| blocked | Verify upgrade/migration from an older Nightshade profile/database. | docs/production-readiness/manual-migration-probe.json; packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart; packages/nightshade_core/test/services/database_migration_test.dart | Required input: An older real Nightshade SQLite database/profile artifact that can be copied and migrated by the probe. |
| incomplete | Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together. | docs/production-readiness/android-emulator-remote-smoke-log.txt, docs/production-readiness/android-emulator-remote-smoke.png, docs/production-readiness/mobile-remote-window-connected.xml; docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt; docs/production-readiness/public-release-external-evidence.json; docs/production-readiness/public-release-audit-report.md; docs/production-readiness/public-release-master-checklist.md; docs/production-readiness/hardware-availability-probe.json | Required input: A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it. Required input: Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices. |
| blocked | Produce a release checklist with known unsupported-by-platform items clearly documented. | docs/production-readiness/public-release-master-checklist.md; docs/production-readiness/public-release-checklist-audit.json; docs/production-readiness/public-release-external-evidence.json; docs/known-limitations.md; docs/supported-hardware-by-platform.md | Required input: Reviewer sign-off evidence for every remaining checklist item, or explicit release-scope removal for items that cannot be satisfied. Checklist audit unchecked=10; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=1/5. |

## Details

### Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable.

- ID: `clean_release_branch_pr`
- Status: `complete`
- Verification rule: Gate check `release_staging` requires a non-main clean branch with no untracked release-critical entries.
- Gap: Current branch=release/hardening-audit-2026-06-16; entryCount=0; untrackedReleaseCritical=0; stagedBranchValidationPassed=true. No blocker-input record found.

Evidence:
- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`

### Split generated/binary/native changes from Dart/UI changes where possible.

- ID: `split_generated_binary_native`
- Status: `complete`
- Verification rule: Split plan assigns dirty entries into generated, binary/evidence, native/bridge, core, UI, and other buckets with pathspec files; owner matrix separates must_ship, generated_only, binary_evidence, and defer_exclude; validator checks the staged index or branch diff against that matrix.
- Gap: Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=8; entryCount=189; ownerMatrixPaths=189; stagedBranchValidationPassed=true.

Evidence:
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`

### Do a Linux release build on an actual Linux environment, not inferred from Windows.

- ID: `linux_release_build`
- Status: `complete`
- Verification rule: Gate requires the external evidence validator to accept Linux build/package evidence.
- Gap: No blocker-input record found.

Evidence:
- `docs/production-readiness/linux-environment-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/linux-release-build-evidence.json`

### Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices.

- ID: `full_hardware_smoke`
- Status: `blocked`
- Verification rule: Gate requires validated external full hardware/control smoke evidence covering all required device classes.
- Gap: Required input: A rig, simulator-backed environment, or remote host that exposes camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety monitor classes, plus permission to run safe control commands.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:hardware-availability --no-select`
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

Evidence:
- `docs/production-readiness/hardware-availability-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/full-hardware-control-smoke-evidence.json`

### Verify upgrade/migration from an older Nightshade profile/database.

- ID: `older_profile_migration`
- Status: `blocked`
- Verification rule: Manual migration probe must run against an older real database/profile and report migrationVerified=true. Synthetic regression tests cover old-schema/profile fixtures but do not replace the real older-profile artifact.
- Gap: Required input: An older real Nightshade SQLite database/profile artifact that can be copied and migrated by the probe.

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

Evidence:
- `docs/production-readiness/manual-migration-probe.json`
- `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart`
- `packages/nightshade_core/test/services/database_migration_test.dart`

### Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together.

- ID: `integrated_remote_headless`
- Status: `incomplete`
- Verification rule: Emulator/mobile and reconnect evidence pass, but second physical LAN/firewall and real remote-control action evidence are still required.
- Gap: Required input: A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it. Required input: Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices.
- Required input: A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it. Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run smoke:headless-lan:windows`
- `dart run melos run audit:public-release-gate --no-select`
- `dart run melos run audit:hardware-availability --no-select`

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

Evidence:
- `docs/production-readiness/android-emulator-remote-smoke-log.txt, docs/production-readiness/android-emulator-remote-smoke.png, docs/production-readiness/mobile-remote-window-connected.xml`
- `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/public-release-audit-report.md`
- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/hardware-availability-probe.json`

### Produce a release checklist with known unsupported-by-platform items clearly documented.

- ID: `release_checklist_known_unsupported`
- Status: `blocked`
- Verification rule: Final checklist gate requires checklist audit evidence with zero unchecked items, zero checked-without-evidence items, known limitations/support docs references, and validated final sign-off evidence.
- Gap: Required input: Reviewer sign-off evidence for every remaining checklist item, or explicit release-scope removal for items that cannot be satisfied. Checklist audit unchecked=10; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=1/5.

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

Evidence:
- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/public-release-checklist-audit.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/known-limitations.md`
- `docs/supported-hardware-by-platform.md`
