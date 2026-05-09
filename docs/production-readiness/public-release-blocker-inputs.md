# Public Release Blocker Inputs

- Source gate: `docs/production-readiness/public-release-gate.json`
- Gate decision: `NOT_READY`
- Open blockers: `7`

This artifact lists the exact missing input or evidence needed to clear each current public-release blocker. It does not satisfy the blockers by itself.

## Summary

| Blocker | Category | Required input |
| --- | --- | --- |
| Clean release branch / PR staging | process | Owner decision on must ship, generated only, binary/evidence, and defer/exclude bucket lists, then a clean non-main release branch/PR validated against that matrix. |
| Linux release build/package evidence | packaging | A working Linux build environment, either repaired WSL Ubuntu, Docker Desktop Linux engine, or another Linux host/CI runner. |
| Full hardware/control smoke | functionality | A rig, simulator-backed environment, or remote host that exposes camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety monitor classes, plus permission to run safe control commands. |
| Older real profile/database migration | data-integrity | An older real Nightshade SQLite database/profile artifact that can be copied and migrated by the probe. |
| Second-device LAN/firewall smoke | networking | A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it. |
| Real remote-control actions | functionality | Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices. |
| Final release checklist/sign-off | process | Reviewer sign-off evidence for every remaining checklist item, or explicit release-scope removal for items that cannot be satisfied. |

## Clean release branch / PR staging

- ID: `release_staging`
- Category: `process`
- Current gate detail: branch=main entryCount=861 untrackedReleaseCritical=323. Split plan buckets=10 pathspecFiles=10 pathspecLines=861 uniquePathspecLines=861. Split-plan pathspec coverage is exact. A clean non-main release branch/PR is still required.
- Local status: Current branch is main with 862 dirty entries and 323 untracked release-critical entries. Split plan has 10 buckets. Owner matrix must_ship paths=742. Latest staged-branch validation passed=false.
- Required input: Owner decision on must ship, generated only, binary/evidence, and defer/exclude bucket lists, then a clean non-main release branch/PR validated against that matrix.

Acceptance criteria:
- Work is on a non-main release branch.
- `dart run melos run audit:release-staging --no-select` reports entryCount=0 and untrackedReleaseCriticalCount=0 for the final PR workspace, or the final PR contains only intentionally staged release files with exclusions documented.
- The owner matrix lists every split-plan bucket under must_ship, generated_only, binary_evidence, or defer_exclude.
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index` or the branch-mode equivalent passes before PR creation.
- The PR description links the staged bucket pathspecs, uses the draft description for each bucket, and explains any excluded bucket.

Rerun commands:
- `dart run melos run audit:release-staging --no-select`
- `dart run melos run audit:release-pr-plan --no-select`
- `dart run melos run audit:release-pr-owner-matrix --no-select`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=index`
- `dart run melos run audit:release-pr-staged-branch --no-select -- --mode=branch --base=main`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `docs/production-readiness/release-staging-audit.json`
- `docs/production-readiness/release-pr-split-plan.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.json`
- `docs/production-readiness/release-pr-owner-decision-matrix.md`
- `docs/production-readiness/release-pr-staged-branch-validation.json`
- `docs/production-readiness/release-pr-pathspecs/*.txt`
- `GitHub PR URL or local branch/review record`

## Linux release build/package evidence

- ID: `linux_release_build`
- Category: `packaging`
- Current gate detail: Linux build environment is unavailable on this host; validated Linux release build/package evidence is missing. External evidence validator did not pass for docs/production-readiness/linux-release-build-evidence.json. Template: docs/production-readiness/external-evidence-templates/linux-release-build-evidence.template.json. Evidence file is missing or is not valid JSON.
- Local status: linuxBuildEnvironmentAvailable=false; wslUsable=false; dockerUsable=false. wsl_ubuntu_uname: Failed to attach disk 'C:\Users\scdou\AppData\Local\wsl\{5f0d72bf-1c39-43a6-bb42-5512156d0383}\ext4.vhdx' to WSL2: The system cannot find the file specified. 
Error code: Wsl/Service/CreateInstance/MountDisk/HCS/ERROR_FILE_NOT_FOUND failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine; check if the path is correct and if the daemon is running: open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified.
- Required input: A working Linux build environment, either repaired WSL Ubuntu, Docker Desktop Linux engine, or another Linux host/CI runner.

Acceptance criteria:
- `dart run melos run build:desktop:linux --no-select` succeeds on Linux.
- Linux package/runtime artifact is recorded with path, size, hash, and native library/permission notes from the package metadata generator or CI workflow.
- Linux-launched headless/dashboard smoke evidence exists from that Linux artifact.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:linux-environment --no-select`
- `dart run melos run build:desktop:linux --no-select`
- `dart run melos run audit:linux-release-package-metadata --no-select`
- `dart run melos run audit:public-release-gate --no-select`

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

## Full hardware/control smoke

- ID: `hardware_control_smoke`
- Category: `functionality`
- Current gate detail: Required real-or-simulator classes missing on this host: filterWheel, rotator, dome, safetyMonitor. Non-simulator gaps: filterWheel, rotator, dome, safetyMonitor. Command/control smoke remains unverified. External evidence validator did not pass for docs/production-readiness/full-hardware-control-smoke-evidence.json. Template: docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json. Evidence file is missing or is not valid JSON.
- Local status: Real-or-simulator classes available here: camera, mount, focuser, guider, weather. Missing real-or-simulator classes: filterWheel, rotator, dome, safetyMonitor. Non-simulator classes available here: camera, mount, focuser, guider, weather. Missing non-simulator classes: filterWheel, rotator, dome, safetyMonitor. Discovery is not command/control smoke.
- Required input: A rig, simulator-backed environment, or remote host that exposes camera, mount, focuser, filter wheel, rotator, guider, dome, weather, and safety monitor classes, plus permission to run safe control commands.

Acceptance criteria:
- Every required device class is discoverable as real or simulator-backed for the smoke environment.
- Connect/disconnect is exercised for each required class.
- Safe read/status command is exercised for each required class.
- Safe control command is exercised where applicable, such as camera short exposure, focuser small move, filter position query/change, rotator angle query/change, guider status, dome status/open-close or simulator equivalent, weather read, and safety state read.
- The smoke log records device IDs, driver types, command results, and any intentionally skipped unsafe action.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:hardware-availability:windows --no-select`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `docs/production-readiness/full-hardware-control-smoke-evidence.json`
- `docs/production-readiness/external-evidence-templates/full-hardware-control-smoke-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/hardware-availability-probe.json`
- `Full hardware/control smoke log with command results`
- `Screenshots or exported dashboard/device-state evidence if manually driven`

## Older real profile/database migration

- ID: `manual_migration`
- Category: `data-integrity`
- Current gate detail: artifactProvided=false sourceExists=false sourceSizeBytes=0 sourceSha256Recorded=false qualifiesAsOlderProfile=false migrationVerified=false missingTables=0 missingDefaultSettings=0.
- Local status: artifactProvided=false; migrationVerified=false. No older real Nightshade database/profile was supplied. Set NIGHTSHADE_OLD_DATABASE or pass --dart-define=NIGHTSHADE_OLD_DATABASE=<path>.
- Required input: An older real Nightshade SQLite database/profile artifact that can be copied and migrated by the probe.

Acceptance criteria:
- Probe runs against a temporary copy of an older real database/profile.
- `artifactProvided=true` and `migrationVerified=true` in `manual-migration-probe.json`.
- Report records source path, source size, source SHA256, original user_version, final user_version, current table set, and required default settings.
- Synthetic old-schema/profile migration regression tests pass without using real user data.

Rerun commands:
- `cd packages/nightshade_core && flutter test test/services/database_migration_test.dart`
- `$env:NIGHTSHADE_OLD_DATABASE="<path-to-old-nightshade.sqlite>"; dart run melos run audit:manual-migration --no-select`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `packages/nightshade_core/test/fixtures/synthetic_old_profile_fixtures.dart`
- `packages/nightshade_core/test/services/database_migration_test.dart`
- `docs/production-readiness/manual-migration-probe.json`
- `docs/production-readiness/manual-migration-probe.md`
- `Path or secure reference to the source old database artifact`

## Second-device LAN/firewall smoke

- ID: `second_device_lan_firewall`
- Category: `networking`
- Current gate detail: No validated artifact proves access from a second physical device/browser through the real firewall/router path. External evidence validator did not pass for docs/production-readiness/second-device-lan-firewall-smoke-evidence.json. Template: docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json. Evidence file is missing or is not valid JSON.
- Local status: Local non-loopback and Android emulator-host-alias smokes exist, but no second physical device/browser evidence exists.
- Required input: A second physical phone, tablet, or laptop on the same LAN, with the Windows firewall/router path used exactly as a real user would use it.

Acceptance criteria:
- Packaged Windows headless server is reached from the second device over the LAN IP, not localhost or emulator alias.
- Dashboard loads with HTML/CSS/JS assets.
- Authenticated token flow succeeds and missing/wrong token fails.
- WebSocket connects and reconnect behavior is observed or logged.
- Evidence records server LAN URL, client device type, network path, timestamp, and screenshots/logs.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run smoke:headless-lan:windows`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `docs/production-readiness/second-device-lan-firewall-smoke-evidence.json`
- `docs/production-readiness/external-evidence-templates/second-device-lan-firewall-smoke-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `Second-device browser screenshot or mobile screenshot`
- `Server log showing second-device client IP`
- `Manual smoke notes with firewall/router path`
- `docs/production-readiness/public-release-audit-report.md update`

## Real remote-control actions

- ID: `real_remote_control_actions`
- Category: `functionality`
- Current gate detail: No validated artifact proves actual remote control actions against real or simulator-backed devices. External evidence validator did not pass for docs/production-readiness/real-remote-control-actions-evidence.json. Template: docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json. Evidence file is missing or is not valid JSON.
- Local status: No artifact proves remote control commands against real or simulator-backed devices. Current host is also missing filterWheel, rotator, dome, safetyMonitor real-or-simulator classes.
- Required input: Permission and a safe test window to issue actual remote control actions from dashboard/mobile/headless APIs against real or simulator-backed devices.

Acceptance criteria:
- Remote client sends at least one safe command per applicable device class.
- Server logs include request IDs, client key/token scope, action, route, and completion status for high-risk commands.
- Device state after each command is read back and recorded.
- Unsafe real-world commands are either performed in simulator mode or explicitly skipped with a safety reason.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:hardware-availability:windows --no-select`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `docs/production-readiness/real-remote-control-actions-evidence.json`
- `docs/production-readiness/external-evidence-templates/real-remote-control-actions-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `Remote-control smoke log with command/result pairs`
- `Dashboard/mobile screenshots showing connected state and command results`
- `Server audit log excerpt for high-risk commands`

## Final release checklist/sign-off

- ID: `final_checklist`
- Category: `process`
- Current gate detail: Checklist items=284 checked=0 unchecked=284 checkedWithoutEvidence=0 knownLimitationsReferenced=true supportedHardwareByPlatformReferenced=true; validated final sign-off evidence is missing. External evidence validator did not pass for docs/production-readiness/final-release-signoff-evidence.json. Template: docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json. Evidence file is missing or is not valid JSON.
- Local status: Checklist items=284 checked=0 unchecked=284 checkedWithoutEvidence=0 knownLimitationsReferenced=true supportedHardwareByPlatformReferenced=true.
- Required input: Reviewer sign-off evidence for every remaining checklist item, or explicit release-scope removal for items that cannot be satisfied.

Acceptance criteria:
- Every completed checklist item has evidence notes.
- Every unchecked release-blocking item is resolved, hidden, or removed from scope.
- Known unsupported-by-platform items are referenced in the known limitations and supported hardware docs.
- Final ship/no-ship decision records date, reviewer, commit/hash, and known limitations.
- `audit:public-release-gate` reports `Decision: READY`.

Rerun commands:
- `dart run melos run audit:public-release-external-evidence --no-select`
- `dart run melos run audit:public-release-checklist --no-select`
- `dart run melos run audit:public-release-gate --no-select`

Expected evidence:
- `docs/production-readiness/final-release-signoff-evidence.json`
- `docs/production-readiness/external-evidence-templates/final-release-signoff-evidence.template.json`
- `docs/production-readiness/public-release-external-evidence.json`
- `docs/production-readiness/public-release-master-checklist.md`
- `docs/production-readiness/public-release-checklist-audit.json`
- `docs/production-readiness/public-release-gate.json`
- `Final release decision record`
