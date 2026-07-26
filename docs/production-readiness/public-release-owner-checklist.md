# Public Release Owner Checklist

- Source audit: `docs/production-readiness/public-release-completion-audit.json`
- Completion audit generated at: `2026-07-21T15:08:51.845627Z`
- Decision: `NOT_ACHIEVED`
- Gate decision: `NOT_READY`
- Completion detail: One or more P0 requirements remain blocked or weakly verified.
- Ready: `false`
- Items: `7`
- Complete: `3`
- Blocked or incomplete: `4`

This owner checklist is generated from structured completion-audit fields. Edit the underlying evidence, not this generated file.

## Source Artifacts

| Artifact | Exists | Generated | Decision | Count | Blockers |
| --- | ---: | --- | --- | ---: | ---: |
| `goal.txt` | `false` | `unknown` | `` | `` | `` |
| `docs/production-readiness/public-release-gate.json` | `true` | `2026-07-21T15:08:43.913071Z` | `NOT_READY` | `21` | `4` |
| `docs/production-readiness/public-release-blocker-inputs.json` | `true` | `2026-07-21T15:08:47.752181Z` | `NOT_READY` | `` | `4` |
| `docs/production-readiness/public-release-external-evidence.json` | `true` | `2026-07-21T15:07:08.990573Z` | `ready=false` | `3` | `` |
| `docs/production-readiness/release-staging-audit.json` | `true` | `2026-07-21T15:07:15.451793Z` | `` | `10217` | `` |
| `docs/production-readiness/release-pr-split-plan.json` | `true` | `2026-07-21T15:07:21.334419Z` | `` | `10217` | `` |
| `docs/production-readiness/release-pr-owner-decision-matrix.json` | `true` | `2026-07-21T15:07:24.568563Z` | `` | `10217` | `` |
| `docs/production-readiness/release-pr-staged-branch-validation.json` | `true` | `2026-07-21T15:07:29.619743Z` | `` | `` | `` |
| `docs/production-readiness/public-release-checklist-audit.json` | `true` | `2026-07-21T15:04:50.951919Z` | `` | `` | `` |

## Summary

| Status | Requirement | Gap |
| --- | --- | --- |
| `blocked` | Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable. | Current branch=feature/v6-make-it-real; entryCount=10217; untrackedReleaseCritical=55; stagedBranchValidationPassed=false. |
| `in_progress` | Split generated/binary/native changes from Dart/UI changes where possible. | Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=10; entryCount=10217; ownerMatrixPaths=10217; stagedBranchValidationPassed=false. |
| `complete` | Do a Linux release build on an actual Linux environment, not inferred from Windows. | No blocker-input record found. |
| `complete` | Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices. | No blocker-input record found. |
| `complete` | Verify upgrade/migration from an older Nightshade profile/database. | No blocker-input record found. |
| `incomplete` | Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together. | No blocker-input record found. |
| `blocked` | Produce a release checklist with known unsupported-by-platform items clearly documented. | Checklist audit unchecked=5; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=3/5. |

## Create a clean release branch/PR from the dirty worktree so the final artifact is reviewable.

- ID: `clean_release_branch_pr`
- Status: `blocked`
- Verification: Gate check `release_staging` requires a non-main clean branch with no untracked release-critical entries.
- Gap: Current branch=feature/v6-make-it-real; entryCount=10217; untrackedReleaseCritical=55; stagedBranchValidationPassed=false.

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
- Gap: Planning artifacts exist, but no final clean PR has staged or excluded those buckets yet. bucketCount=10; entryCount=10217; ownerMatrixPaths=10217; stagedBranchValidationPassed=false.

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
- Status: `complete`
- Verification: Gate requires the external evidence validator to accept Linux build/package evidence.
- Gap: No blocker-input record found.

Required input:

- None recorded.
Rerun commands:

- `None recorded`
Acceptance criteria:

- None recorded.
Expected evidence:

- `None recorded`
Current evidence references:

- `docs/production-readiness/linux-environment-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/linux-release-build-evidence.json`

## Run a full hardware smoke pass with real or simulator-backed camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety devices.

- ID: `full_hardware_smoke`
- Status: `complete`
- Verification: Gate requires validated external full hardware/control smoke evidence covering all required device classes.
- Gap: No blocker-input record found.

Required input:

- None recorded.
Rerun commands:

- `None recorded`
Acceptance criteria:

- None recorded.
Expected evidence:

- `None recorded`
Current evidence references:

- `docs/production-readiness/hardware-availability-probe.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/full-hardware-control-smoke-evidence.json`

## Verify upgrade/migration from an older Nightshade profile/database.

- ID: `older_profile_migration`
- Status: `complete`
- Verification: Manual migration probe must run against an older release-authentic database/profile and report migrationVerified=true. The checked-in v4.3.0 fixture must be generated by the tagged v4.3.0 database code, not hand-authored SQL.
- Gap: No blocker-input record found.

Required input:

- None recorded.
Rerun commands:

- `None recorded`
Acceptance criteria:

- None recorded.
Expected evidence:

- `None recorded`
Current evidence references:

- `docs/production-readiness/manual-migration-probe.json`
- `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart`
- `packages/nightshade_core/test/services/database_migration_test.dart`

## Verify headless auth, LAN opt-in, dashboard, mobile remote client, and WebSocket reconnect behavior together.

- ID: `integrated_remote_headless`
- Status: `incomplete`
- Verification: Emulator/mobile and reconnect evidence pass, but second physical LAN/firewall and real remote-control action evidence are still required.
- Gap: No blocker-input record found.

Required input:

- A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it.
Rerun commands:

- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run smoke:headless-lan:windows`
- `dart run melos run audit:public-release-gate --no-select`
Acceptance criteria:

- Packaged Windows headless server is reached from the second device over the LAN IP, not localhost or emulator alias.
- Dashboard loads with HTML/CSS/JS assets.
- Authenticated token flow succeeds and missing/wrong token fails.
- WebSocket connects and reconnect behavior is observed or logged.
- Evidence records server LAN URL, client device type, network path, timestamp, and screenshots/logs.
Expected evidence:

- `docs/production-readiness/second-device-lan-firewall-smoke-evidence.json`
- `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `Second-device browser screenshot or mobile screenshot`
- `Server log showing second-device client IP`
- `Manual smoke notes with firewall/router path`
- `docs/production-readiness/public-release-audit-report.md update`
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
- Gap: Checklist audit unchecked=5; checkedWithoutEvidence=0; knownLimitationsReferenced=true; supportedHardwareByPlatformReferenced=true. External evidence checks passing=3/5.

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

