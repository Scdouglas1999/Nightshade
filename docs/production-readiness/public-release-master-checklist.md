# Public Release Master Checklist

Purpose: persistent audit list for deciding whether Nightshade is ready for a public release.

Use this as a hard gate, not a nice-to-have review.

Do not mark an item complete unless all of the following are true:
- The intended behavior is clear.
- The current implementation matches that behavior.
- The UI makes the behavior understandable to a first-time user.
- Failure and edge cases are handled cleanly.
- The result has been verified with real evidence: code review, manual QA, automated test, or all three.

## Audit Method

- [ ] For each feature, document the intended user-facing behavior before judging the implementation.
- [ ] For each feature, verify the implemented behavior in code and in the running UI.
- [ ] For each feature, compare intended behavior vs actual behavior and record any mismatch.
- [ ] For each feature, review the happy path, likely user mistakes, and failure/recovery paths.
- [ ] For each feature, verify that the UX explains the system state clearly enough for a first-time user.
- [ ] For each feature, verify persistence, restart behavior, and cross-screen state consistency where applicable.
- [ ] For each feature, capture release notes: approved, blocked, or out of scope.

## Evidence Template

Attach short notes under completed items using this format:

`Evidence: code=[path], manual=[flow/repro], tests=[command/test], result=[pass/blocker/note]`

Example:

`Evidence: code=packages/nightshade_app/lib/screens/diagnostics/diagnostics_screen.dart, manual=session picker with >50 sessions, tests=flutter test packages/nightshade_app, result=pass`

## Evidence Rules

- [ ] Every completed item has a short note with evidence.
- [ ] Every release-blocking issue found during review is linked to a concrete file, flow, or repro.
- [ ] Every unchecked item is treated as not yet release-approved.
- [ ] Any feature that cannot pass this checklist is hidden or explicitly removed from the release scope.
- [ ] Every item marked complete has been checked against both code structure and user experience, not just compilation.
- [ ] Every blocker is categorized as functionality, UX, performance, security, packaging, or process.

## Global Release Gates

- [ ] `dart run melos run audit:public-release-gate` reports `Decision: READY`.
  Evidence, 2026-05-05:
  `dart run melos run audit:public-release-gate --no-select` passed and wrote
  `docs/production-readiness/public-release-gate.json` plus
  `docs/production-readiness/public-release-gate.md`. Current result is
  `Decision: NOT_READY`, with 12 passing checks and 7 blockers. This item cannot
  be checked until the gate reports `READY`.
  Blocker-input evidence, 2026-05-05:
  `dart run melos run audit:public-release-blocker-inputs --no-select` passed
  and wrote `docs/production-readiness/public-release-blocker-inputs.json` plus
  `docs/production-readiness/public-release-blocker-inputs.md`, mapping each
  open gate blocker to required input, acceptance criteria, rerun commands, and
  expected evidence. This does not satisfy any blocker by itself.
  External-evidence verifier, 2026-05-05:
  `dart run melos run audit:public-release-external-evidence --no-select`
  passed and wrote
  `docs/production-readiness/public-release-external-evidence.json`,
  `docs/production-readiness/public-release-external-evidence.md`, and
  templates under `docs/production-readiness/external-evidence-templates/`.
  Current result is 0 of 5 external evidence checks passing because no
  completed external evidence files have been supplied. The verifier now
  requires referenced evidence files to exist, validates Linux artifact
  size/SHA256 against the file, requires second-device WebSocket reconnect
  observation, requires hardware command results with state readback and
  real/simulator backing type, and requires final sign-off to name the current
  git HEAD, include a non-empty release notes artifact, and match a completed
  checklist audit. Release notes must not be the template, must include the
  required release-note sections, must reference the support/limitations/gate
  artifacts, and must not contain unreplaced template placeholders.
  Gate self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-gate:self-test --no-select` passed
  against temporary fixtures. It verifies the public release gate rejects failed
  aggregate verifier self-test artifacts and stale release PR split plans whose
  `sourceGeneratedAt`, path set, and entry count no longer match the staging
  audit, and verifies the gate can report `READY` when all required evidence
  fixtures are complete.
  Blocker-input self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-blocker-inputs:self-test --no-select`
  passed against temporary blocked and ready fixtures. It verifies all seven
  current public-release blocker IDs produce non-empty required inputs,
  acceptance criteria, rerun commands, expected evidence, and current gate
  detail, and verifies a ready gate produces zero blocker-input records.
  Verifier self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-external-evidence:self-test --no-select`
  passed against temporary fixtures. It verifies the external evidence verifier
  rejects missing evidence, accepts Linux artifact evidence only when file size
  and SHA256 match, rejects localhost-style LAN smoke evidence, rejects
  physical-LAN evidence without WebSocket reconnect observation, accepts a valid
  physical-LAN evidence fixture, rejects incomplete hardware and remote-control
  command fixtures that lack state readback, device coverage, or real/simulator
  backing type, accepts valid hardware and remote-control fixtures, rejects
  template/incomplete final sign-off evidence, and accepts a valid final
  sign-off fixture with completed checklist audit and release notes.
  Completion-audit evidence, 2026-05-05:
  `dart run melos run audit:public-release-completion --no-select` passed and
  wrote `docs/production-readiness/public-release-completion-audit.json` plus
  `docs/production-readiness/public-release-completion-audit.md`. It maps the
  `goal.txt` P0 requirements to concrete evidence and reports
  `NOT_ACHIEVED`, with 0 complete P0 checks and 7 blocked or incomplete P0
  checks.
  Completion-audit self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-completion:self-test --no-select`
  passed against temporary blocked and achieved fixtures. It verifies the
  completion audit reports `decision=NOT_ACHIEVED` separately from
  `gateDecision=NOT_READY` for blocked fixtures, can report
  `decision=ACHIEVED` when all P0 gate evidence is complete, and marks the
  generated/binary/native split requirement complete only after the release
  staging gate has passed with a split-plan artifact present.
  Checklist-audit evidence, 2026-05-05:
  `dart run melos run audit:public-release-checklist --no-select` passed and
  wrote `docs/production-readiness/public-release-checklist-audit.json` plus
  `docs/production-readiness/public-release-checklist-audit.md`. It found 284
  checklist items, 0 checked items, 284 unchecked items, 0 checked items
  without evidence notes, and confirmed that the checklist references the known
  limitations and supported-hardware-by-platform docs. This item remains
  unchecked until the gate reports `READY`.
  Checklist-audit self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-checklist:self-test --no-select`
  passed against temporary blocked and complete checklist fixtures. It verifies
  item counts, checked-without-evidence detection, known-limitations and
  supported-hardware reference detection, and `--fail-on-unchecked` behavior
  for both blocked and complete checklists.
  Aggregate self-test evidence, 2026-05-05:
  `dart run melos run audit:public-release-self-tests --no-select` passed and
  ran all six release verifier self-tests: gate, blocker inputs, external
  evidence, completion audit, checklist audit, and release staging/PR split plan
  coverage. It wrote `docs/production-readiness/public-release-self-tests.json`
  plus `docs/production-readiness/public-release-self-tests.md` with 6 passed
  scripts, 0 failed scripts, exit codes, and per-script durations.
- [ ] `dart run melos run analyze:production` passes with `Production: errors=0, warnings=0`.
  Evidence, 2026-05-05: command passed. Analyzer rollup reported
  `Production: errors=0, warnings=0`; full analyzer output still includes 14
  non-production warnings and 233 infos. Report:
  `docs/production-readiness/analyzer-rollup.json`.
- [ ] `dart run melos run audit:fail-closed` passes.
  Evidence, 2026-05-05: command passed with
  `Fail-closed policy checks passed.` It generated
  `docs/production-readiness/fail-closed-audit.json` plus
  `docs/production-readiness/fail-closed-audit.md`; the public release gate now
  consumes the JSON artifact and reports 0 violations.
- [ ] `dart run melos run audit:placeholders` passes.
  Evidence, 2026-05-05: command passed with 9 known runtime marker hits,
  0 high-risk hits, and no new high-risk markers compared to
  `docs/production-readiness/highrisk-baseline.txt`.
- [ ] `dart run melos run audit:ui-consistency` runs and produces a reviewed UI consistency report.
  Evidence, 2026-05-05: command passed and produced
  `.ui_consistency_audit.txt` plus
  `docs/production-readiness/ui-consistency-audit.json`. Reviewed summary:
  `docs/production-readiness/ui-consistency-audit.md`. Current result is 203
  `raw_material_color` findings, all classified as
  `intentional_image_overlay`; `raw_button_style`, `large_radius`,
  `empty_callback`, `headless_route_not_advertised`, and semantic raw Material
  color findings are zero. The public release gate now consumes the JSON
  artifact and treats intentional image/overlay colors as report-only.
- [ ] `cargo check --manifest-path native/nightshade_native/bridge/Cargo.toml` passes.
  Evidence, 2026-05-05: command passed on Windows with no Rust warnings. This
  does not satisfy the separate Linux release build/package gate.
  Linux environment probe, 2026-05-05:
  `dart run melos run audit:linux-environment --no-select` passed and wrote
  `docs/production-readiness/linux-environment-probe.json` plus
  `docs/production-readiness/linux-environment-probe.md`. It reports
  `linuxBuildEnvironmentAvailable=false`: WSL Ubuntu cannot start because its
  `ext4.vhdx` is missing, and Docker Desktop's Linux engine is not reachable.
  This is blocker evidence only, not Linux build/package evidence.
- [ ] Desktop app tests pass.
  Evidence, 2026-05-05: `dart run melos run test --no-select` passed across
  all 10 Flutter packages, including `nightshade_desktop`.
- [ ] Android release APK builds successfully.
  Evidence, 2026-05-05: `dart run melos run build:mobile:android --no-select`
  passed and produced
  `apps/mobile/build/app/outputs/flutter-apk/app-release.apk` at 147,298,900
  bytes with SHA256
  `72D1CBCEA03EF496B0C0D2AD03B5D6BDB12041D603067298AE1D0AEA846F4ABF`.
  `apps/mobile/pubspec.yaml` now declares `cupertino_icons`, resolving the
  prior missing Cupertino font warning in the release icon tree-shaker. Android
  install/runtime smoke has emulator evidence below.
  Emulator install/launch smoke, 2026-05-05: installed the APK on
  `nightshade_release_smoke_api35` with `adb install -r`, launched
  `com.nightshade.mobile`, confirmed PID `3357`, confirmed resumed
  `com.nightshade.mobile/com.example.nightshade_mobile.MainActivity`, and found
  no `FATAL EXCEPTION`/`AndroidRuntime` crash logs in the captured log window.
  Screenshot:
  `docs/production-readiness/android-emulator-launch-smoke.png`.
- [ ] Core package tests pass.
  Evidence, 2026-05-05: `dart run melos run test --no-select` passed across
  all 10 Flutter packages, including `nightshade_core`.
- [ ] App package tests pass.
  Evidence, 2026-05-05: `dart run melos run test --no-select` passed across
  all 10 Flutter packages, including `nightshade_app`.
- [ ] Plugin package tests pass.
  Evidence, 2026-05-05: `dart run melos run test --no-select` passed across
  all 10 Flutter packages, including `nightshade_plugins`.
- [ ] Any generated bindings or generated database files that are part of the release are up to date.
- [ ] Database migration tests verify older schemas converge to the current table set and default settings.
  Evidence, 2026-05-05: `flutter test test/services/database_migration_test.dart`
  from `packages/nightshade_core` passed. The test covers the schema-12 upgrade
  to the current Drift-managed table set plus default settings convergence.
- [ ] Packaged assets required by shipped features are present in the release bundle.
  Evidence, 2026-05-05: `dart run melos run audit:windows-bundle` passed
  against `apps/desktop/build/windows/x64/runner/Release`, verifying required
  Windows binaries, native DLLs, Flutter asset manifests, and dashboard assets.
  It generated `docs/production-readiness/windows-bundle-audit.json` plus
  `docs/production-readiness/windows-bundle-audit.md`; the public release gate
  now consumes the JSON artifact and reports 57 files scanned, 0 missing
  required files, and 0 disallowed files.
- [ ] Workspace packages declare direct dependencies for shipped `lib/` imports.
  Evidence, 2026-05-05:
  `dart run melos run audit:dependency-hygiene --no-select` passed and
  generated `docs/production-readiness/dependency-hygiene.json` plus
  `docs/production-readiness/dependency-hygiene.md`. It scanned 10 workspace
  packages and found 0 missing direct dependencies for `package:` imports under
  each package `lib/` tree. The public release gate now consumes the JSON
  artifact and treats dependency-hygiene violations as blockers.
- [ ] Platform unsupported items match `docs/production-readiness/feature-parity-matrix.md`, in-app Platform Capabilities, and `/api/info.platformCapabilities`.
  Evidence, 2026-05-05: `flutter test test/models/platform_capabilities_test.dart`
  from `packages/nightshade_core` passed. The test locks ASCOM COM, Alpaca,
  INDI, Native SDK, and Simulator status values to the public support matrix.
  Runtime `/api/info.platformCapabilities` and in-app visual smoke remain part
  of integrated release verification.
  Backend UI-copy evidence, 2026-05-05:
  `flutter test test/models/driver_backend_description_test.dart` from
  `packages/nightshade_core` passed. The test locks backend descriptions so
  ASCOM COM stays labeled Windows-only, cross-platform ASCOM points to Alpaca,
  and Native SDK/INDI copy remains release- and capability-scoped. Equipment
  tutorial copy now matches that wording.
  API-doc wording evidence, 2026-05-05:
  `docs/api/data-models.md`, `docs/api/bridge-api.md`,
  `native/nightshade_native/bridge/src/api.rs`, and
  `packages/nightshade_bridge/lib/src/api.dart` now use release-scoped backend
  language for ASCOM COM, Alpaca, INDI, Native SDK, and simulator discovery.
  Remote response evidence, 2026-05-05:
  `flutter test test/headless_api/auth_middleware_test.dart` from
  `apps/desktop` passed. The test now verifies `/api/info.platformCapabilities`
  and `/api/self-test.deviceDrivers` carry the same release-scoped driver matrix
  in headless responses.
  In-app matrix evidence, 2026-05-05:
  `flutter test test/screens/settings/platform_capabilities_settings_test.dart`
  from `packages/nightshade_app` passed. The test renders Connection Settings
  and verifies the in-app Platform Capabilities section shows the release-scoped
  backend matrix.
- [ ] Headless route registration, `/api/info`, generated OpenAPI, and `NetworkBackend` call sites stay aligned.
  Evidence, 2026-05-05: `dart run melos run audit:headless-api-contract --no-select`
  passed and generated
  `docs/production-readiness/headless-api-contract-audit.json` plus
  `docs/production-readiness/headless-api-contract-audit.md`. It reported 295
  registered routes, 295 advertised routes, 293 advertised HTTP routes, 270
  generated OpenAPI paths, 255 `NetworkBackend` routes, and 0 drift in every
  comparison. Focused test evidence:
  `flutter test test/headless_api/network_backend_contract_test.dart` from
  `apps/desktop` passed.
- [ ] Public supported-hardware docs match `docs/supported-hardware-by-platform.md`, platform capabilities, and hardware smoke evidence.
  Evidence, 2026-05-05: `docs/supported-hardware-by-platform.md`,
  `docs/production-readiness/feature-parity-matrix.md`, `docs/known-limitations.md`,
  and `PlatformCapabilityMatrix` now agree that Simulator support is
  workflow-specific and capability-gated. Hardware or simulator-backed smoke is
  still required before checking this item.
  Hardware availability probe, 2026-05-05:
  `dart run melos run audit:hardware-availability:windows --no-select` passed
  and wrote `docs/production-readiness/hardware-availability-probe.json` plus
  `docs/production-readiness/hardware-availability-probe.md`. It discovered
  real-or-simulator camera, mount, focuser, guider, and weather candidates from
  the packaged Windows headless server, but no real-or-simulator filter wheel,
  rotator, dome, or safety monitor on this host. The probe now reports both
  real-or-simulator and non-simulator coverage; both are false here. This is
  discovery-only blocker evidence, not command/control smoke evidence.
- [ ] Remote clients reject too-old, too-new, missing, or malformed server API versions before switching into network-control mode.
  Evidence, 2026-05-05: `flutter test test/models/remote_api_compatibility_test.dart test/backend/network_backend_websocket_test.dart`
  from `packages/nightshade_core` passed. `NetworkBackend.connect()` now checks
  `/api/info.version` before opening `/events` and rejects too-old, too-new,
  missing, and malformed versions before reporting `connected`.
  Additional evidence, 2026-05-05:
  `flutter test test/backend/network_backend_websocket_test.dart` from
  `packages/nightshade_core` passed after adding regression coverage that
  `NetworkBackend.discoverDevices()` accepts the headless API `deviceType`
  response field and still supports the legacy `type` fallback.
- [ ] Headless runtime self-test reports backend, platform, device-driver availability, storage paths, auth mode, and route count via `/api/self-test`.
  Evidence, 2026-05-05: `apps/desktop/test/headless_api/auth_middleware_test.dart`
  launches `HeadlessApiServer` and verifies authenticated `/api/self-test`
  reports platform, auth mode/scopes, backend, connected-device probe,
  `deviceDrivers`, storage paths, database status, and endpoint count matching
  `/api/info.endpoints`.
  Packaged smoke, 2026-05-05: `dart run melos run smoke:headless:windows`
  launches the Windows release executable in headless mode and verifies
  authenticated `/api/self-test` responds from the packaged app, reports token
  auth mode, advertises admin/control/view scopes, and matches `/api/info`
  endpoint count.
- [ ] Headless API docs are generated from the route table and available at `/api/openapi.json`.
  Evidence, 2026-05-05: `flutter test test/headless_api` from `apps/desktop`
  passed, including OpenAPI generation from the advertised route table and
  route-parameter conversion. Runtime fetch of `/api/openapi.json` in a launched
  headless server remains part of integrated smoke.
  Packaged smoke, 2026-05-05: `dart run melos run smoke:headless:windows`
  verifies `/api/openapi.json` is available to a view-scoped token from the
  packaged Windows headless app.
- [ ] Headless contract tests compare registered server routes, advertised `/api/info` and OpenAPI routes, and `NetworkBackend` call sites.
  Evidence, 2026-05-05: `apps/desktop/test/headless_api/network_backend_contract_test.dart`
  now checks registered route parity with `/api/info`, `NetworkBackend`
  call-site parity, and OpenAPI coverage for every advertised HTTP route.
- [ ] Headless control endpoints reject oversized request bodies, with explicit larger limits only for image-processing JSON and backup upload.
  Evidence, 2026-05-05: `apps/desktop/test/headless_api/route_metadata_test.dart`
  verifies the 1 MiB default control limit, 64 MiB image-processing exceptions,
  and 256 MiB backup upload exception.
  Structured route-policy evidence, 2026-05-05:
  `dart run melos run audit:headless-route-policy --no-select` passed and
  generated `docs/production-readiness/headless-route-policy-audit.json` plus
  `docs/production-readiness/headless-route-policy-audit.md` with 0 policy
  issues.
- [ ] Headless control endpoints apply per-client, per-endpoint rate limits with stricter limits for slew, park/unpark, device connect/disconnect, sequence start/stop, dome movement, and backup restore.
  Evidence, 2026-05-05: `apps/desktop/test/headless_api/route_metadata_test.dart`
  verifies high-risk limits for device connect/disconnect, mount slew/park/unpark,
  dome open/close/slew, backup restore/upload-restore, and sequencer start/stop.
  Structured route-policy evidence, 2026-05-05:
  `dart run melos run audit:headless-route-policy --no-select` reported 19
  high-risk policies and 9 default-limited control policies.
- [ ] Headless high-risk remote commands produce audit log entries with request ID, client key, action, route, and completion status.
  Evidence, 2026-05-05: metadata tests verify audit action mapping for the
  high-risk command set above; runtime log capture in a launched server remains
  part of integrated smoke.
  Structured route-policy evidence, 2026-05-05:
  `docs/production-readiness/headless-route-policy-audit.json` verifies the
  expected audit action names for the high-risk route set. This is metadata
  evidence only; runtime log capture remains part of real remote-control smoke.
- [ ] Headless scoped tokens enforce view, control, and admin access boundaries.
  Evidence, 2026-05-05: `flutter test test/headless_api` covers scoped auth
  policy and middleware, including view/control/admin access boundaries and
  legacy token admin compatibility.
  Packaged smoke, 2026-05-05: `dart run melos run smoke:headless:windows`
  verifies a missing token is rejected for `/api/self-test`, an admin token can
  call `/api/self-test`, a view token can call `/api/openapi.json`, and a view
  token is rejected from `/api/camera/expose`.
  LAN-address smoke, 2026-05-05:
  `dart run melos run smoke:headless-lan:windows` verifies the same token
  boundaries through a non-loopback IPv4 URL exposed by the packaged Windows
  headless executable.
- [ ] Mobile and remote clients send WebSocket heartbeats, consume `pong` replies from desktop and WebRTC servers, and reconnect after heartbeat timeout.
  Evidence, 2026-05-05: `flutter test test/backend/network_backend_websocket_test.dart`
  from `packages/nightshade_core` passed for ping/pong heartbeat handling and
  silent-socket timeout disconnect. Browser dashboard and mobile-client
  integrated reconnect smoke have packaged Windows evidence below.
  Desktop server heartbeat evidence, 2026-05-05:
  `flutter test test/headless_api/auth_middleware_test.dart` from
  `apps/desktop` verifies `/events` sends heartbeat `ping`, accepts client
  `pong`, and closes stale clients that do not answer before the heartbeat
  timeout.
  Packaged smoke, 2026-05-05: `dart run melos run smoke:headless:windows`
  verifies the packaged Windows headless `/events` WebSocket accepts a
  view-token query parameter and replies to `ping` with `pong`. Reconnect after
  timeout remains open for browser/mobile integrated smoke.
  Browser smoke, 2026-05-05:
  `dart run melos run smoke:dashboard-browser:windows` verifies the rendered
  dashboard opens its WebSocket from headless Chrome using a view token.
  Browser reconnect smoke, 2026-05-05:
  `dart run melos run smoke:dashboard-reconnect:windows` verifies the packaged
  browser dashboard logs WebSocket disconnect, reports `api.isWsConnected`
  false, reconnects after the packaged headless server restarts on the same
  port, and reports `api.isWsConnected` true again.
  LAN-address smoke, 2026-05-05:
  `dart run melos run smoke:headless-lan:windows` verifies `/events` accepts a
  view-token query parameter and returns `pong` over a non-loopback IPv4 URL.
  Mobile remote smoke, 2026-05-05:
  `dart run melos run smoke:mobile-android-remote:windows` passed. It installed
  the rebuilt APK on `emulator-5554`, connected to packaged Windows headless
  through emulator host alias `10.0.2.2:<port>`, and reached the connected
  Catalog Setup flow. Log evidence showed WebSocket `connected` and background
  discovery completion. This verifies initial mobile WebSocket connection, not
  heartbeat timeout/reconnect behavior.
  Mobile reconnect smoke, 2026-05-05:
  `dart run melos run smoke:mobile-android-reconnect:windows` passed. It uses
  the same packaged Windows headless plus Android release APK flow, kills the
  packaged headless server, restarts it on the same port, and verifies the
  Android client's `NetworkBackend` logs a disconnected state, reconnect
  scheduling, and `WebSocket connected successfully` after restart. Reconnect
  log: `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt`.
- [ ] Release branch staging area is clean and intentionally scoped.
  Evidence, 2026-05-05:
  `dart run melos run audit:release-staging --no-select` passed and generated
  `docs/production-readiness/release-staging-audit.json` plus
  `docs/production-readiness/release-staging-audit.md`. The audit confirms this
  item cannot be checked yet: the current `main` worktree is still broad and
  dirty, with hundreds of changed/untracked entries split across app UI,
  headless/remote, native Rust, generated files, binary/evidence artifacts,
  docs, tests, and release tooling.
  Split-plan evidence, 2026-05-05:
  `dart run melos run audit:release-pr-plan --no-select` passed and generated
  `docs/production-readiness/release-pr-split-plan.json` plus
  `docs/production-readiness/release-pr-split-plan.md`, assigning the dirty set
  into proposed review buckets. It also generated exact bucket pathspec files in
  `docs/production-readiness/release-pr-pathspecs/` with matching
  `git add --pathspec-from-file=...` commands. This is scoping evidence only;
  no clean release branch or reviewed staging set exists yet.
  Gate coverage evidence, 2026-05-05:
  `dart run melos run audit:public-release-gate --no-select` now validates the
  split-plan/pathspec coverage directly. The current gate reports 10 pathspec
  files, 805 pathspec lines, 805 unique paths, and exact coverage between
  `release-staging-audit.json`, `release-pr-split-plan.json`, and
  `docs/production-readiness/release-pr-pathspecs/`. This still does not make
  the current `main` worktree clean or reviewed.
  Staging/split-plan self-test evidence, 2026-05-05:
  `dart run melos run audit:release-staging-pr-plan:self-test --no-select`
  passed against a temporary dirty git fixture. It verifies classification for
  modified, deleted, generated, binary, release-critical, and out-of-scope
  paths, verifies dirty/untracked-critical fail modes, and verifies each
  generated pathspec matches its PR bucket exactly.
- [ ] No critical feature depends on untracked or accidentally omitted files.
  Evidence, 2026-05-05:
  `dart run melos run audit:release-staging --no-select` reports untracked
  release-critical files in headless auth/route metadata, release docs/evidence,
  production smoke tools, native Rust additions, generated database files, and
  public app/core code. This item remains blocked until those files are either
  intentionally staged into the release branch or explicitly excluded with
  evidence that shipped features do not depend on them.
  Split-plan evidence, 2026-05-05:
  `docs/production-readiness/release-pr-split-plan.md` separates those
  untracked and modified paths into review buckets so each can be staged or
  excluded deliberately. The generated pathspec files make the stage set
  reproducible, but they do not prove the files are staged or unnecessary.
- [ ] Migration, backup, and restore docs are published in `docs/migration-backup-restore.md` and match the BackupService, Settings UI, and headless backup routes.
  Evidence, 2026-05-05: guide reviewed against
  `packages/nightshade_core/lib/src/services/backup_service.dart`,
  `packages/nightshade_app/lib/screens/settings/backup_screen.dart`, and
  `apps/desktop/lib/headless_api/handlers/backup_handlers.dart`; updated route
  list to include `/api/backup/auto-save`. Focused tests pass for v2 backup
  metadata category counts and current `TargetHeader` sequence restore.

## App-Wide Audit Standards

- [ ] Every major feature has a documented "supposed to work like this" summary before sign-off.
- [ ] Every major feature has been checked for "implemented differently than implied by UI copy or docs".
- [ ] Every major screen has a clear purpose on first open.
- [ ] Every major screen has acceptable empty, loading, success, and error states.
- [ ] No screen contains fake telemetry, placeholder values, misleading labels, or dead controls.
- [ ] No screen contains visible encoding defects or broken formatting.
- [ ] Copy is consistent across shell, settings, dialogs, toasts, and docs.
- [ ] User actions produce timely, understandable feedback.
- [ ] Long-running actions show progress or a clearly communicated busy state.
- [ ] Errors are actionable and do not expose raw internal noise unless in diagnostics/dev flows.
- [ ] State changes remain consistent across desktop shell, dialogs, overlays, and secondary views.
- [ ] Layouts remain usable on supported desktop and mobile breakpoints.
- [ ] Keyboard and pointer navigation are both workable for critical flows.
- [ ] Focus order and modal dismissal behavior are sane.
- [ ] Scroll behavior, overflow handling, and long-text truncation are acceptable on major screens.
- [ ] Busy states, disabled states, and retry states are visually distinct and understandable.
- [ ] Multi-step flows do not leave the user unsure what to do next.
- [ ] Design-system gallery renders buttons, cards, inputs, tabs, chips, alerts, and status pills across dark, light, compact, and red-night themes.
  Evidence, 2026-05-05: `packages/nightshade_ui/lib/src/widgets/design_system_gallery.dart`
  renders button variants, card variants, text/dropdown/checkbox/switch inputs,
  tabs, chips, status pills, and info/warning/error alerts.
  `flutter test test/design_system_gallery_test.dart` from
  `packages/nightshade_ui` passed for dark, compact light, and red-night theme
  coverage.
- [ ] UI consistency audit classifies remaining raw Material colors, raw button styles, large radii, fake callbacks, and unadvertised headless routes.
- [ ] The structure of providers/services/screens remains understandable and maintainable.
- [ ] No critical feature is implemented in a way that is obviously race-prone, misleading, or tightly coupled beyond reason.

## First-Run and Core Journeys

- [ ] First launch experience is coherent.
- [ ] First launch does not expose broken or irrelevant settings.
- [ ] App can launch without configured hardware and still feel intentional.
- [ ] App can restart cleanly after settings changes.
- [ ] App can recover after a crash or forced close.
- [ ] Upgrade path from an existing install does not corrupt settings or state.
  Evidence required: `flutter test test\services\database_migration_test.dart` plus a manual upgrade from an older real profile/database.
  Automated evidence, 2026-05-05: migration test passed. Manual upgrade from an
  older real profile/database is still required before this item can be checked.
  Manual artifact probe, 2026-05-05:
  `dart run melos run audit:manual-migration --no-select` passed and wrote
  `docs/production-readiness/manual-migration-probe.json` plus
  `docs/production-readiness/manual-migration-probe.md`. The current run
  reports `artifactProvided=false` and `migrationVerified=false`, so this item
  remains blocked until an older real Nightshade SQLite database/profile is
  supplied through `NIGHTSHADE_OLD_DATABASE` or
  `--dart-define=NIGHTSHADE_OLD_DATABASE=<path>` and the migrated copy verifies
  against the current schema. The probe and public release gate now also
  require the supplied source artifact to record a non-zero file size and
  SHA256 so migration evidence can be tied to a concrete database file.
- [ ] New user can discover the main workflows without dead ends.
- [ ] Shutdown/quit while operations are active behaves safely and predictably.
- [ ] Relaunch after incomplete work restores the right amount of context without misleading the user.

## Shell, Navigation, and Windowing

- [ ] Global shell layout is coherent on first launch.
- [ ] Primary navigation reflects the most important workflows.
- [ ] Route changes preserve or intentionally discard state.
- [ ] Back behavior is predictable on mobile and desktop.
- [ ] Dialogs, sheets, overlays, and popovers do not conflict with each other.
- [ ] Status bar reflects real state and remains readable during active operations.
- [ ] Multi-window, external-link, and browser-launch actions behave correctly if in release scope.

## Dashboard

- [ ] Dashboard loads without missing widgets or broken layout.
- [ ] Widgets shown on the dashboard reflect real state.
- [ ] Widget picker and dashboard customization work correctly.
- [ ] Empty dashboard state is intentional and usable.
- [ ] Dashboard remains readable with no connected devices.
- [ ] Dashboard remains readable with several connected devices and active operations.
- [ ] Dashboard performance is acceptable during active imaging/sequencing.

## Equipment and Connection Management

- [ ] Discovery works for supported device types.
- [ ] Connect flow works for camera.
- [ ] Connect flow works for mount.
- [ ] Connect flow works for focuser.
- [ ] Connect flow works for guider.
- [ ] Connect flow works for filter wheel.
- [ ] Connect flow works for rotator if included in release scope.
- [ ] Connect flow works for weather and safety devices if included in release scope.
- [ ] Disconnect/reconnect updates UI state correctly.
- [ ] Connection failures produce clear and actionable messages.
- [ ] Profile selection and active profile switching behave correctly.
- [ ] Device cards/panels do not show stale state after reconnect.
- [ ] Quick connect and profile-driven connection flows are understandable.
- [ ] Unsupported or unavailable devices fail cleanly.
- [ ] Simulated/dev-only device paths are hidden or clearly unavailable in public release flows.

## Imaging

- [ ] Imaging screen layout is clear and stable.
- [ ] Exposure controls reflect real camera state.
- [ ] Capture start/abort/status all work correctly.
- [ ] Last image / preview behavior matches user expectations.
- [ ] Cooling, gain, offset, and binning controls behave correctly.
- [ ] Save path handling is truthful and robust.
- [ ] Imaging still behaves sensibly if no save path is configured.
- [ ] Errors during capture do not leave UI in a stuck state.
- [ ] Annotation overlays and image tools do not break the main imaging flow.
- [ ] Imaging UX is usable both idle and during active capture.
- [ ] Capture-related warnings and destructive actions are explicit before data can be lost.

## Focus and Autofocus

- [ ] Manual focuser controls work and reflect actual device state.
- [ ] Autofocus start/cancel/status flows work correctly.
- [ ] Temperature compensation UI is truthful.
- [ ] Focus model / offset / compensation features are understandable.
- [ ] Lack of focus model data is handled gracefully.
- [ ] Focus overlays and dialogs do not trap or confuse the user.

## Guiding

- [ ] Guiding connect/disconnect behaves correctly.
- [ ] Start/stop guiding works correctly.
- [ ] Dither behavior is correctly surfaced.
- [ ] Guide state, graphs, and status panels remain truthful during activity.
- [ ] Lost-star / failure states produce the right UI and sequencer interaction.
- [ ] PHD2-specific controls behave consistently with the actual backend state.

## Sequencer

- [ ] Sequence editor loads and remains stable with realistic sequences.
- [ ] Sequence run state is reflected truthfully across shell and sequencer UI.
- [ ] Start, pause, resume, stop, skip, and completion flows all work correctly.
- [ ] Current node, progress, timing, and messages are truthful.
- [ ] Preflight validation catches meaningful issues before run.
- [ ] Runtime failures, pauses, and recovery states are understandable.
- [ ] Checkpoints and resume behavior work correctly.
- [ ] Long-running sequences do not drift into stale or contradictory UI states.
- [ ] Sequence library/history/template flows are coherent.
- [ ] Mobile and compact-width sequencer behavior remains usable.
- [ ] Sequencer interactions with guiding, autofocus, weather/safety, and device disconnects behave correctly.

## Planetarium

- [ ] Planetarium opens without broken rendering or layout.
- [ ] Search and object selection work correctly.
- [ ] Object details match selected object.
- [ ] Filters, tabs, and overlays are coherent.
- [ ] Slew-related actions match actual mount capability and state.
- [ ] Sidebars and mobile variants remain usable.
- [ ] Planetarium remains performant with realistic catalog content.

## Planner

- [ ] Planner loads successfully with realistic data.
- [ ] Planner has good empty/loading/error states.
- [ ] Plan suggestions are understandable and actionable.
- [ ] Planner actions integrate correctly with sequencer/planetarium flows.
- [ ] Planner remains usable on small widths.
- [ ] Planner assumptions, scoring, and constraints are not overstated in the UI.

## Suggestions

- [ ] Suggestions screen is coherent and not over-promising.
- [ ] Filters and recommendation logic are understandable.
- [ ] Altitude and visibility displays are truthful.
- [ ] Suggestion actions lead somewhere useful.

## Analytics

- [ ] Analytics screen is navigable and visually coherent.
- [ ] Science/insight panels only expose features that actually work.
- [ ] Session-level analytics match stored data.
- [ ] Export flows behave correctly.
- [ ] Empty/no-data analytics states are designed, not broken.
- [ ] Mobile and narrow-width layouts remain usable.
- [ ] Any modeled or estimated values are clearly identified where user interpretation matters.

## Diagnostics

- [ ] Diagnostics screen loads without assertion failures.
- [ ] Session selection is stable even with many sessions.
- [ ] Diagnostics data corresponds to the selected session.
- [ ] No-data diagnostics states are intentional and understandable.
- [ ] Charts/vectors/residual views remain readable and performant.
- [ ] Error paths do not expose users to raw crashes or broken layout.

## Weather and Safety

- [ ] Weather screen loads without broken layout.
- [ ] Safety state shown to the user matches the backend truth.
- [ ] Unsafe conditions trigger the correct UI and operational behavior.
- [ ] Missing weather/safety data respects configured fail mode.
- [ ] Radar/maps/widgets are stable and understandable if included in release scope.
- [ ] Weather/safety warnings are not easy to miss.

## Framing, Polar Alignment, Flat Wizard, and Other Capture Utilities

- [ ] Framing screen behaves correctly with realistic targets and device state.
- [ ] Polar alignment flow works end to end.
- [ ] Flat wizard flow works end to end.
- [ ] These utilities do not leave global state or devices in a bad state after exit.
- [ ] Validation and preconditions are clear before users begin these flows.

## Observation Log and Observing Lists

- [ ] Observation log create/edit/export flows work.
- [ ] Observing list create/edit/use flows work.
- [ ] Planetarium/planner integration with logs/lists behaves correctly.
- [ ] Empty states are clear and useful.

## Settings

- [ ] Settings navigation is coherent and not cluttered with unsupported features.
- [ ] Every visible setting has an actual effect.
- [ ] Setting labels, helper text, and side effects are truthful.
- [ ] Settings persist across restart.
- [ ] Changing settings at runtime updates UI and services correctly where promised.
- [ ] If restart is required, that is stated clearly and consistently.
- [ ] Duplicate/conflicting settings surfaces are not exposed to users.

## Remote Access

- [ ] Remote Access settings match the actual server behavior.
- [ ] Desktop remote access can be enabled and disabled reliably.
- [ ] Port changes rebind safely and do not leave zombie servers behind.
- [ ] Localhost access works as intended.
- [ ] LAN access works as intended.
  Local LAN-address evidence, 2026-05-05:
  `dart run melos run smoke:headless-lan:windows` passed. It launches the
  packaged Windows headless executable with authentication enabled, reaches it
  through a non-loopback IPv4 URL (`http://172.19.96.1:<port>` in the latest
  run), verifies `/api/self-test` reports `bindMode=lan`, confirms missing
  credentials are rejected, confirms view-token control requests are rejected,
  serves dashboard assets, and completes WebSocket ping/pong. A second
  physical device/browser and firewall/router path still need manual smoke
  before this item can be checked.
  Mobile emulator evidence, 2026-05-05:
  `dart run melos run smoke:mobile-android-remote:windows` reached packaged
  Windows headless from Android emulator through `10.0.2.2:<port>` using the
  admin token. This proves emulator-host remote reachability but does not
  replace second-device LAN/firewall smoke.
- [ ] Pairing flow works from a second device/browser.
- [ ] Bad token / stale token / missing device ID are handled clearly.
- [ ] Dashboard only reports connected when authenticated control actually works.
- [ ] Remote viewers are counted truthfully.
- [ ] Share/pairing dialog copy is truthful for local-only vs LAN vs authenticated access.
- [ ] Remote-access failure states are visible and actionable.
- [ ] Pairing endpoint has acceptable abuse resistance for public release.
- [ ] Remote-control actions are fail-closed where required.
- [ ] Rapid enable/disable/reconfigure actions do not race into inconsistent server state.

## Desktop Web Dashboard

- [ ] Dashboard assets are packaged in release builds.
  Evidence, 2026-05-05: after adding `web_dashboard/css/` and
  `web_dashboard/js/` to `apps/desktop/pubspec.yaml`, `flutter build windows`
  from `apps/desktop` produced release assets for `web_dashboard/index.html`,
  `web_dashboard/css/dashboard.css`, `web_dashboard/js/api.js`, and
  `web_dashboard/js/app.js` under
  `apps/desktop/build/windows/x64/runner/Release/data/flutter_assets/`.
  Linux/macOS package asset verification remains open.
- [ ] Browser dashboard loads from the desktop server without missing assets.
  Evidence, 2026-05-05: `apps/desktop/test/headless_api/auth_middleware_test.dart`
  now verifies `/dashboard`, `/dashboard/css/dashboard.css`,
  `/dashboard/js/api.js`, and `/dashboard/js/app.js` are publicly served with
  expected content types. `flutter test test/headless_api/auth_middleware_test.dart`
  and `dart run melos run test --no-select` both passed.
  Packaged smoke, 2026-05-05: `dart run melos run smoke:headless:windows`
  verifies the same dashboard HTML/CSS/JS assets are served by the packaged
  Windows headless executable.
  Browser smoke, 2026-05-05:
  `dart run melos run smoke:dashboard-browser:windows` launches the packaged
  Windows headless executable and renders `/dashboard` in headless Chrome. It
  verifies a view token reaches `Connected`, the dashboard API client and
  WebSocket initialize, 6 panels render, and no JavaScript exceptions or
  `console.error` calls occur. This required changing
  `apps/desktop/web_dashboard/index.html` to reference
  `/dashboard/css/dashboard.css`, `/dashboard/js/api.js`, and
  `/dashboard/js/app.js` so packaged browser loads do not resolve assets as
  authenticated `/css` and `/js` requests.
  LAN-address smoke, 2026-05-05:
  `dart run melos run smoke:headless-lan:windows` verifies the same dashboard
  HTML/CSS/JS assets are served over a non-loopback IPv4 URL by the packaged
  Windows headless executable.
- [ ] Pairing UI is understandable to a non-technical user.
- [ ] Connection state is truthful.
- [ ] Device panels reflect real backend state.
- [ ] Auth-required server mode is handled correctly.
- [ ] Wrong token / wrong device ID / revoked device UX is acceptable.
- [ ] WebSocket reconnect behavior does not fake success.
  Browser smoke, 2026-05-05:
  `dart run melos run smoke:dashboard-browser:windows` verifies the initial
  rendered dashboard WebSocket connection from Chrome.
  Browser reconnect smoke, 2026-05-05:
  `dart run melos run smoke:dashboard-reconnect:windows` verifies the rendered
  dashboard observes a WebSocket disconnect while REST connection state remains
  established, logs the reconnecting state, then reconnects to the packaged
  headless server after restart on the same port.
  Mobile reconnect smoke, 2026-05-05:
  `dart run melos run smoke:mobile-android-reconnect:windows` verifies the
  Android remote client logs disconnect, reconnect scheduling, and WebSocket
  reconnection after the packaged Windows headless server restarts on the same
  port. This is emulator-host-alias evidence, not second-device LAN/firewall
  evidence.
- [ ] Polling + WebSocket interaction stays consistent.
- [ ] Browser refresh, tab duplication, and reconnect from sleep behave correctly.

## Plugins

- [ ] Public plugin UI is hidden if plugins are not a supported public feature.
- [ ] Plugin lifecycle is stable if plugin framework ships in the build.
- [ ] Example/demo plugins are not exposed to end users.
- [ ] Docs match the actual plugin story being shipped.

## Mobile Experience

- [ ] Android release APK installs and launches on a supported device or emulator.
  Build evidence, 2026-05-05: `dart run melos run build:mobile:android --no-select`
  passed and produced
  `apps/mobile/build/app/outputs/flutter-apk/app-release.apk` at 147,298,900
  bytes with SHA256
  `72D1CBCEA03EF496B0C0D2AD03B5D6BDB12041D603067298AE1D0AEA846F4ABF`.
  Emulator evidence, 2026-05-05: installed Android Emulator `36.5.11` and
  `system-images;android-35;google_apis;x86_64`, created AVD
  `nightshade_release_smoke_api35`, booted it as `emulator-5554`, installed
  `apps/mobile/build/app/outputs/flutter-apk/app-release.apk`, launched
  `com.nightshade.mobile`, confirmed the app process stayed alive and
  `MainActivity` was resumed, captured no fatal crash logs, and saved screenshot
  evidence at `docs/production-readiness/android-emulator-launch-smoke.png`.
- [ ] Mobile client can connect to an authenticated packaged headless server.
  Emulator-host evidence, 2026-05-05:
  `dart run melos run smoke:mobile-android-remote:windows` passed. The smoke
  starts the rebuilt packaged Windows headless executable on a reserved port
  with admin/view/control tokens, verifies `/api/info` reports `version=2.5.0`,
  verifies unreachable INDI/Alpaca address probes degrade to
  `200 {"devices":[]}`, installs the rebuilt release APK on `emulator-5554`,
  clears app data and logcat, launches `com.nightshade.mobile`, enters
  `10.0.2.2:<port>` and the admin token, and reaches the connected Catalog
  Setup flow. Clean log evidence showed `NetworkBackend` WebSocket connected,
  no Nightshade auth denial, no `Internal server error`, no fatal Android crash
  signature, no QuickStart disposed-ref error, discovery cached 10 headless
  devices, and `AutoDiscovery` completed. Screenshot/XML/log:
  `docs/production-readiness/android-emulator-remote-smoke.png`,
  `docs/production-readiness/mobile-remote-window-connected.xml`, and
  `docs/production-readiness/android-emulator-remote-smoke-log.txt`. This does
  not cover a physical second device, firewall/router behavior, or real
  remote-control actions.
  Reconnect evidence, 2026-05-05:
  `dart run melos run smoke:mobile-android-reconnect:windows` passed and saved
  `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt`
  showing disconnected state, reconnect scheduling, and WebSocket reconnection
  after the packaged headless server restarted on the same port.
- [ ] Mobile navigation is coherent and not overloaded.
- [ ] Mobile shell remains usable with the current route set.
- [ ] Primary actions remain reachable on mobile.
- [ ] Text scaling and responsive layout do not break critical screens.
- [ ] Overlays, dialogs, and bottom sheets do not stack into unusability.
- [ ] Touch targets, gesture conflicts, and keyboard overlays are acceptable on supported mobile devices.

## Accessibility, Copy, and Localization

- [ ] No visible copy corruption or encoding issues remain.
- [ ] Critical flows have understandable labels and helper text.
- [ ] Warning/destructive actions are explicit.
- [ ] User-visible copy does not overstate capabilities.
- [ ] Localization coverage is acceptable for touched public flows.
- [ ] Tooltips and status labels clarify truncated or advanced information where needed.

## Data Integrity, Persistence, and Recovery

- [ ] Settings persistence is correct.
- [ ] Session persistence is correct.
- [ ] Sequence checkpoints and run history are correct.
- [ ] Observation/analytics/diagnostic data remains internally consistent.
- [ ] Corrupt or missing local data is handled safely.
- [ ] File exports create correct output in correct locations.

## Notifications, Alerts, and Feedback

- [ ] Toasts, snackbars, banners, and alerts appear at the right times.
- [ ] Notifications do not contradict the visible screen state.
- [ ] Repeated failures do not spam the user into ignoring important alerts.
- [ ] Critical warnings are noticeable without being opaque or overwhelming.

## Native Bridge and Backend Integrity

- [ ] Dart and Rust bridge types remain in sync.
- [ ] Device operations fail safely on timeout or disconnect.
- [ ] Native warnings are understood and not hiding shipped defects.
  Evidence, 2026-05-05: removed the Windows build warning set from
  `native/nightshade_native/imaging/src/phd2.rs`,
  `native/nightshade_native/bridge/src/devices.rs`, and
  `native/nightshade_native/bridge/src/builtin_guider.rs`.
  `cargo check --manifest-path native/nightshade_native/bridge/Cargo.toml`,
  `cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml`,
  and `cargo test --manifest-path native/nightshade_native/bridge/Cargo.toml builtin_guider`
  all passed on Windows. The targeted Rust test needs
  `apps/desktop/build/windows/x64/runner/Release` on `PATH` for DLL resolution.
- [ ] Generated bridge files match current native API.
- [ ] Desktop DLLs and packaged binaries match the intended build output.
  Evidence, 2026-05-05: `dart run melos run build:desktop:windows --no-select`
  passed, and direct `flutter build windows` from `apps/desktop` produced
  `apps/desktop/build/windows/x64/runner/Release/nightshade_desktop.exe`. The
  release folder includes `nightshade_bridge.dll`, `libraw.dll`, `sqlite3.dll`,
  Flutter/plugin DLLs, Fujifilm `FF*API.dll` files, and `XAPI.dll`. Linux and
  final installer/package verification remain open before this item can be
  checked.

## Performance and Stability

- [ ] App remains responsive during long-running operations.
- [ ] No obvious rebuild-loop or sync-I/O-on-build regressions remain.
- [ ] Repeated screen navigation does not leak state or degrade performance.
- [ ] Remote access, imaging, and sequencing can run together without obvious instability.
- [ ] App remains stable after extended uptime.

## Security and Privacy

- [ ] Remote control is authenticated whenever it leaves localhost.
- [ ] Headless secure setup docs cover auth modes, token use, LAN binding, firewall ports, self-test, OpenAPI, and WebSocket heartbeat verification.
  Evidence, 2026-05-05: `docs/headless-secure-setup.md` covers loopback,
  authenticated LAN, unauthenticated LAN, token and scoped-token usage,
  firewall ports, `/api/self-test`, `/api/openapi.json`, and WebSocket
  ping/pong heartbeat verification.
- [ ] Headless secure setup docs explain view, control, and admin token scopes.
  Evidence, 2026-05-05: `docs/headless-secure-setup.md` defines `view`,
  `control`, and `admin` scopes and distinguishes legacy admin tokens from
  narrower view/control tokens.
- [ ] Public endpoints are intentional and minimal.
- [ ] Pairing/token flows do not leak secrets unnecessarily.
- [ ] Revoked devices actually lose access.
- [ ] Remote failures default to safe behavior.
- [ ] Sensitive operations are not exposed anonymously.

## Updater and Release Delivery

- [ ] Update UI is truthful about current version, available version, and install state.
- [ ] Update checks fail cleanly when offline or misconfigured.
- [ ] Release packaging does not break updater expectations if updater ships in scope.
- [ ] Install/upgrade messaging does not over-promise platform support.

## Packaging and Public Release Operations

- [ ] Release notes match the actual shipped feature set.
- [ ] Release notes use `docs/release-notes-template.md` and include verification evidence, supported hardware, migration, security, and rollback sections.
  Evidence, 2026-05-05: `docs/release-notes-template.md` includes sections for
  supported platforms, supported hardware and drivers, security and remote
  access, migration and compatibility, known limitations, verification summary,
  upgrade notes, and rollback plan. It remains a template and must be filled
  with release-candidate-specific evidence before this item can be checked.
- [ ] Migration, backup, and restore guide is published with backup contents/exclusions, local restore, headless restore, replace-vs-merge behavior, migration verification, and rollback.
  Evidence, 2026-05-05: `docs/migration-backup-restore.md` covers backup
  contents and exclusions, local Settings restore, headless backup routes,
  uploaded restore, merge versus `replaceExisting` behavior, migration
  verification, and rollback. Manual upgrade from an older real profile remains
  a separate release blocker.
- [ ] README/docs do not advertise unsupported end-user features.
  Evidence, 2026-05-05:
  `docs/getting-started/first-image.md` was reviewed and updated to point to
  `docs/supported-hardware-by-platform.md`, `docs/known-limitations.md`,
  `docs/migration-backup-restore.md`, and `docs/headless-secure-setup.md`
  before users attempt hardware, remote, or upgrade-sensitive workflows. The
  guide now frames filter wheels, cooling, guiding, mount slews, and remote
  access as capability-dependent. A focused local Markdown link check for the
  guide passed. This item remains unchecked until the full documentation set is
  reviewed.
  Additional evidence, 2026-05-05:
  `docs/index.md` and `docs/getting-started/installation.md` now avoid
  broad unverified claims about shipped macOS/Linux packages, mobile remote
  modes, WebRTC, and OTA updates. They direct users to release notes,
  `docs/supported-hardware-by-platform.md`, and `docs/known-limitations.md` for
  release-specific support. Focused local Markdown link checks for both files
  passed.
  Additional evidence, 2026-05-05:
  `docs/getting-started/first-connection.md` now avoids broad unverified claims
  about native SDK plug-and-play support, INDI/macOS/Linux parity, Alpaca
  feature availability, filter wheel movement, guiding, simulator mode, and
  automatic profile reconnect. It links to supported hardware, known
  limitations, migration/backup guidance, headless secure setup, and
  driver/firewall troubleshooting. A focused local Markdown link check passed.
  Additional evidence, 2026-05-05:
  `docs/troubleshooting/common-issues.md` now avoids broad unverified claims
  about native SDK, Linux, macOS, INDI, Alpaca, ASCOM, PHD2, runtime
  dependency, and save-path support. It directs users to release notes,
  `docs/supported-hardware-by-platform.md`, `docs/known-limitations.md`, and
  the driver, permissions, and firewall troubleshooting pages. A focused local
  Markdown link check passed.
  Link evidence, 2026-05-05:
  `dart run melos run audit:docs-links --no-select` scanned 95 Markdown files
  under `docs/`, checked 144 local links, found 0 broken local links, and wrote
  `docs/production-readiness/docs-link-audit.json` plus
  `docs/production-readiness/docs-link-audit.md`.
- [ ] Supported hardware claims are conservative and list known native SDK/platform gaps.
  Evidence, 2026-05-05:
  `docs/supported-hardware-by-platform.md` lists backend support by platform
  for ASCOM COM, Alpaca, INDI, Native SDK, and Simulator; device-category
  expectations for camera, mount, focuser, filter wheel, rotator, guider, dome,
  weather/safety, and cover/calibrator; native SDK/vendor packaging caveats;
  known release-planning gaps; and the release artifacts that must agree before
  a public support claim is made. This remains unchecked until the completed
  release notes and external Linux/hardware evidence match the matrix.
- [ ] Known limitations are published in `docs/known-limitations.md` with impact, workaround, blocker status, and owner/issue.
  Evidence, 2026-05-05: `docs/known-limitations.md` includes acceptance rules,
  current release-candidate limitations with impact/workaround/blocker status
  and tracking references, plus unsupported-by-platform entries aligned with the
  support matrix.
- [ ] Troubleshooting docs cover INDI, Alpaca, ASCOM, PHD2, permissions, drivers, and firewall failures.
  Evidence, 2026-05-05: `docs/troubleshooting/indi.md`,
  `docs/troubleshooting/alpaca.md`, `docs/troubleshooting/ascom.md`,
  `docs/troubleshooting/phd2.md`, `docs/troubleshooting/permissions.md`,
  `docs/troubleshooting/drivers.md`, and `docs/troubleshooting/firewall.md`
  exist and include quick checks, likely failure causes, and release-gate
  evidence notes.
- [ ] No internal/dev-only files are accidentally bundled in the public release.
  Evidence, 2026-05-05: `dart run melos run audit:windows-bundle` scanned 57
  files in the Windows release bundle and found 0 disallowed files. The audit
  rejects `.gitkeep`, debug sidecars, logs, and test/coverage directories. Linux
  and final installer artifact audits remain open.
- [ ] Build scripts/package scripts produce the intended outputs.
  Evidence, 2026-05-05: `melos.yaml` now uses the local Melos entrypoint for
  `analyze`, `format`, `test`, `generate`, and platform build scripts.
  `dart run melos run test --no-select` and
  `dart run melos run build:desktop:windows --no-select` both passed on
  Windows. Linux and macOS package outputs remain unverified.
- [ ] Final release candidate has a reviewed, intentional git staging set.
  Evidence, 2026-05-05:
  `docs/production-readiness/release-staging-audit.md` and
  `docs/production-readiness/release-pr-split-plan.md` are available as staging
  scope reports, and `docs/production-readiness/release-pr-pathspecs/` contains
  bucket pathspecs for a future clean branch. No final reviewed staging set
  exists yet.

## Audit Log

- [ ] Maintain a running list of blockers discovered during review.
- [ ] Maintain a running list of "acceptable known limitations" with explicit justification in `docs/known-limitations.md`.
- [ ] Record final ship/no-ship decision with date, reviewer, and commit/hash under review.

## Final Sign-Off

- [ ] Code review of all release-critical areas is complete.
- [ ] Manual QA of primary user journeys is complete.
- [ ] Manual QA of failure and edge cases is complete.
- [ ] Security review of remote-access/public endpoints is complete.
- [ ] Release candidate has no unresolved blockers.
- [ ] Public release blocker input checklist has either been fully satisfied or superseded by newer gate evidence.
  Evidence, 2026-05-05:
  `docs/production-readiness/public-release-blocker-inputs.md` lists all 7
  current gate blockers and their required input/evidence. It remains an open
  checklist because the gate still reports `Decision: NOT_READY`.
- [ ] External evidence verifier passes for Linux build, full hardware/control, second-device LAN/firewall, real remote-control actions, and final sign-off.
  Evidence, 2026-05-05:
  `docs/production-readiness/public-release-external-evidence.md` exists and
  generated templates for the required external evidence files. It currently
  reports 0 passing checks, so this item remains blocked.
- [ ] Completion audit maps every P0 `goal.txt` public-release requirement to complete direct evidence.
  Evidence, 2026-05-05:
  `docs/production-readiness/public-release-completion-audit.md` maps the P0
  requirements to evidence and gaps. It currently reports `NOT_ACHIEVED`, so
  this item remains blocked.
- [ ] Decision: ship.
