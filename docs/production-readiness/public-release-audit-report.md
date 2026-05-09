# Public Release Audit Report

Date: 2026-05-06
Base state under review: dirty local worktree, no clean release branch/PR
Decision: `NOT READY - P0 EVIDENCE INCOMPLETE`

This report is the evidence-backed companion to [public-release-master-checklist.md](/C:/Users/scdou/Documents/Nightshade2/docs/production-readiness/public-release-master-checklist.md).

`NOT READY` here means the repository has useful release evidence, but the
current local state is not a public release candidate. Do not publish from this
worktree until the P0 evidence below is complete on a clean release branch.

## Current P0 Blockers

- Public release gate: not ready. The consolidated gate reports
  `Decision: NOT_READY`, with 17 checks passing and 7 blockers still open. Use
  `dart run melos run audit:public-release-gate --no-select` for the current
  ship/no-ship summary.
- Clean release branch/PR: not verified. The current worktree contains a broad
  mix of modified and untracked files, so the releasable artifact is not yet
  intentionally scoped. The release staging audit now classifies the dirty set
  into review buckets and shows many untracked release-critical files still
  need an explicit stage-or-exclude decision before a PR. The release PR split
  plan turns that audit into proposed review buckets, but it is scoping
  evidence only and does not replace a clean branch/PR.
- Linux release build: not verified. A Windows-local build or analyzer pass does
  not prove that Linux packaging, native libraries, permissions, and runtime
  entry points work on Linux. A WSL2 Ubuntu check on this machine could not
  start because the distribution VHDX is missing, and Docker Desktop's Linux
  engine is not running. The Linux environment probe records this host
  blocker, but Linux evidence still needs a working Linux environment.
- Hardware smoke: not verified. Camera, mount, focuser, filter wheel, rotator,
  guider, dome, weather, and safety workflows still need real or
  simulator-backed evidence. The Windows packaged availability probe found
  camera, mount, focuser, guider, and weather candidates, but no
  real-or-simulator filter wheel, rotator, dome, or safety monitor on this
  host, so a full hardware/control smoke cannot be completed here. The current probe now
  distinguishes real-or-simulator coverage from non-simulator coverage; both
  are false for filter wheel, rotator, dome, and safety monitor on this host.
- Migration/upgrade: not fully verified. Automated migration coverage is useful,
  but public release sign-off still requires a manual upgrade from an older real
  Nightshade profile/database. The manual migration probe now records whether
  such an artifact was supplied and can migrate a temporary copy when one is
  provided; the current run confirms no older real artifact is available in this
  workspace.
- Integrated remote/headless behavior: not verified end to end. Headless auth,
  authenticated non-loopback binding, local browser dashboard rendering, and an
  Android-emulator-to-packaged-headless mobile connection/reconnect now have smoke
  evidence, including browser WebSocket reconnect after a packaged server
  restart. A second physical device, firewall/router behavior, and real
  remote-control actions still need to be tested.
- Release checklist evidence: incomplete. Unchecked items in
  [public-release-master-checklist.md](/C:/Users/scdou/Documents/Nightshade2/docs/production-readiness/public-release-master-checklist.md)
  remain release-blocking until they have concrete evidence notes. The
  checklist audit now reports 284 checklist items, 0 checked items, 284
  unchecked items, and 0 checked items without evidence notes; the blocker
  input checklist records the exact owner input, acceptance criteria, and
  expected evidence required to clear each open P0 gate.

## Current Evidence Snapshot

- Production analyzer evidence, 2026-05-05:
  `dart run melos run analyze:production` passed. Analyzer rollup reported
  `Production: errors=0, warnings=0`; full analyzer output still includes 14
  non-production warnings and 233 infos. The generated report is
  `docs/production-readiness/analyzer-rollup.json`.
- UI consistency audit, 2026-05-05:
  `dart run melos run audit:ui-consistency` -> 203 findings, all
  `raw_material_color:intentional_image_overlay`; `large_radius`,
  `raw_button_style`, `empty_callback`, and `headless_route_not_advertised` are
  zero. Reviewed summary:
  `docs/production-readiness/ui-consistency-audit.md`; generated report:
  `.ui_consistency_audit.txt`.
- Focused analyzer passes completed for the latest UI-radius cleanup:
  `flutter analyze --no-fatal-infos` on the touched `nightshade_app` files and
  `packages/nightshade_ui/lib/src/components/nightshade_switch.dart`.
- Migration and backup evidence, 2026-05-05:
  `flutter test test/services/database_migration_test.dart` in
  `packages/nightshade_core` passed. Focused backup tests passed for legacy
  setting coercion, nested v2 metadata category counts, and current
  `TargetHeader` sequence-node restore. Manual upgrade from an older real
  profile/database remains unverified.
- Manual migration probe evidence, 2026-05-05:
  `dart run melos run audit:manual-migration --no-select` passed and generated
  `docs/production-readiness/manual-migration-probe.json` plus
  `docs/production-readiness/manual-migration-probe.md`. The default run
  intentionally does not fail without an artifact, but records
  `artifactProvided=false` and `migrationVerified=false`. To satisfy the manual
  migration gate, rerun the probe with an older real SQLite database via
  `NIGHTSHADE_OLD_DATABASE` or
  `--dart-define=NIGHTSHADE_OLD_DATABASE=<path>` and require
  `migrationVerified=true`. Verified migration evidence must now also include
  a non-zero source file size and SHA256 so the report identifies the concrete
  older database artifact under test.
- Synthetic migration regression evidence, 2026-05-06:
  `dart run melos run audit:migration-regression --no-select` passed and
  generated `docs/production-readiness/migration-regression-audit.json` plus
  `docs/production-readiness/migration-regression-audit.md`. The audit verifies
  the synthetic schema-20 duplicate-active-profile fixture, the database
  migration regression tests, and the manual migration probe separation text
  are all present. Focused verification:
  `flutter test test/services/database_migration_test.dart` passed in
  `packages/nightshade_core` with 9 tests, including the synthetic schema-20
  profile fixture and schema-12 table/default-settings convergence. This
  reduces migration risk without replacing the required older real
  profile/database artifact gate.
- Headless and remote API evidence, 2026-05-05:
  `flutter test test/headless_api` in `apps/desktop` passed, covering scoped
  auth middleware/policy, registered route advertising, NetworkBackend route
  call-site parity, OpenAPI generation from the advertised route table, request
  body limits, endpoint rate limits, high-risk audit action metadata, and the
  `/api/self-test` runtime response sections for platform, server auth, backend,
  device drivers, storage paths, database, and route count.
  `flutter test test/backend/network_backend_websocket_test.dart` in
  `packages/nightshade_core` passed, covering ping/pong heartbeat handling and
  silent WebSocket timeout disconnect behavior. The same test now covers
  `NetworkBackend.discoverDevices()` accepting the headless API `deviceType`
  field, plus the legacy `type` fallback.
  `flutter test test/headless_api/auth_middleware_test.dart` in `apps/desktop`
  passed, covering the desktop `/events` server heartbeat path: server `ping`,
  client `pong`, and stale-client closure when no `pong` arrives before the
  timeout.
- Platform capability evidence, 2026-05-05:
  `flutter test test/models/platform_capabilities_test.dart` in
  `packages/nightshade_core` passed. The static platform capability model now
  matches the public driver backend matrix for ASCOM COM, Alpaca, INDI, Native
  SDK, and Simulator, including workflow-specific simulator
  `capability-gated` status. Linux package/runtime verification remains open.
- Backend UI copy evidence, 2026-05-05:
  `flutter test test/models/driver_backend_description_test.dart` in
  `packages/nightshade_core` passed. Driver backend tooltip/label copy now
  keeps ASCOM COM explicitly Windows-only, points cross-platform ASCOM users to
  Alpaca, and scopes Native SDK and INDI wording to packaged SDK libraries and
  reachable INDI servers. Equipment tutorial copy was updated to match the same
  release-scoped backend language.
- Backend API documentation wording evidence, 2026-05-05:
  `docs/api/data-models.md`, `docs/api/bridge-api.md`,
  `native/nightshade_native/bridge/src/api.rs`, and
  `packages/nightshade_bridge/lib/src/api.dart` now describe discovery backends
  with the same scope: Windows-only ASCOM COM, Alpaca network devices or
  bridges, reachable INDI servers, Native SDK paths bundled for the current
  release, and simulator paths only where the workflow is enabled.
- Remote capability-response evidence, 2026-05-05:
  `flutter test test/headless_api/auth_middleware_test.dart` in `apps/desktop`
  passed. The self-test coverage now asserts that public `/api/info` and
  protected `/api/self-test` both expose `platformCapabilities` /
  `deviceDrivers` with ASCOM COM supported only on Windows, cross-platform ASCOM
  directed through Alpaca, Native SDK support scoped to packaged libraries, and
  INDI support scoped to a reachable server/driver.
- In-app platform capability matrix evidence, 2026-05-05:
  `flutter test test/screens/settings/platform_capabilities_settings_test.dart`
  in `packages/nightshade_app` passed. The widget test renders Connection
  Settings and verifies the in-app Platform Capabilities section shows ASCOM
  COM, ASCOM Alpaca, Native SDK, and INDI with release-scoped availability and
  capability text.
- Platform-gated backend selection evidence, 2026-05-05:
  `flutter test test/screens/equipment/backend_selector_chips_test.dart` in
  `packages/nightshade_app` passed. The backend selector now uses the shared
  platform capability matrix to disable unsupported backends; the test verifies
  ASCOM COM is visible but not selectable on Linux while Alpaca remains
  selectable.
- Linux environment probe evidence, 2026-05-05:
  `dart run melos run audit:linux-environment --no-select` passed and generated
  `docs/production-readiness/linux-environment-probe.json` plus
  `docs/production-readiness/linux-environment-probe.md`. It reports
  `linuxBuildEnvironmentAvailable=false`: WSL Ubuntu cannot start because its
  `ext4.vhdx` is missing, and Docker Desktop's Linux engine is unavailable at
  `npipe:////./pipe/dockerDesktopLinuxEngine`. This is environment blocker
  evidence only; it does not satisfy the Linux release build/package gate.
- Remote version negotiation evidence, 2026-05-05:
  `flutter test test/models/remote_api_compatibility_test.dart test/backend/network_backend_websocket_test.dart`
  in `packages/nightshade_core` passed. `NetworkBackend.connect()` now checks
  `/api/info.version` before opening the WebSocket and refuses too-old,
  too-new, missing, or malformed server versions before entering `connected`.
- Native bridge evidence, 2026-05-05:
  `cargo check --manifest-path native/nightshade_native/bridge/Cargo.toml`
  passed on Windows with no Rust warnings. Targeted built-in guider Rust tests
  also passed when run with the Windows release DLL folder on `PATH`:
  `cargo test --manifest-path native/nightshade_native/bridge/Cargo.toml builtin_guider`.
  Linux release build/package verification remains open.
- Windows desktop build evidence, 2026-05-05:
  `dart run melos run build:desktop:windows --no-select` passed after the build
  scripts were updated to use the local Melos entrypoint. A direct
  `flutter build windows` from `apps/desktop` also passed and produced
  `apps/desktop/build/windows/x64/runner/Release/nightshade_desktop.exe`. The
  release folder contains `nightshade_bridge.dll`, `libraw.dll`, `sqlite3.dll`,
  Flutter/plugin DLLs, Fujifilm `FF*API.dll` files, and `XAPI.dll`. The
  Windows build script now completes without the previous Rust warning list;
  Linux release build/package verification remains open.
- Browser dashboard packaging evidence, 2026-05-05:
  The Windows release bundle now includes
  `data/flutter_assets/web_dashboard/index.html`,
  `data/flutter_assets/web_dashboard/css/dashboard.css`,
  `data/flutter_assets/web_dashboard/js/api.js`, and
  `data/flutter_assets/web_dashboard/js/app.js`. This required explicitly
  listing `web_dashboard/css/` and `web_dashboard/js/` in
  `apps/desktop/pubspec.yaml`. Focused headless API tests still pass after the
  packaging change, including coverage that `/dashboard`,
  `/dashboard/css/dashboard.css`, `/dashboard/js/api.js`, and
  `/dashboard/js/app.js` are served without auth with the expected content
  types.
- Windows bundle audit evidence, 2026-05-05:
  `dart run melos run audit:windows-bundle` passed against
  `apps/desktop/build/windows/x64/runner/Release`, scanning 57 files with 0
  missing required files and 0 disallowed files. The audit verifies required
  desktop binaries, native DLLs, Flutter asset manifests, dashboard assets, and
  rejects dev placeholders such as `.gitkeep`, debug artifacts, logs, and test
  directories.
- Packaged headless Windows smoke evidence, 2026-05-05:
  `dart run melos run smoke:headless:windows` passed. The smoke launches the
  packaged `nightshade_desktop.exe --headless` on a free local port with admin,
  view, and control tokens, then verifies public `/api/info`, protected
  `/api/self-test`, token auth mode, advertised admin/control/view scopes,
  self-test endpoint-count parity with `/api/info`, scoped OpenAPI access,
  view-token rejection on a control route, dashboard HTML/CSS/JS serving, and
  WebSocket `/events` ping/pong. LAN exposure, mobile remote-client behavior,
  and reconnect-after-timeout smoke have additional focused evidence below, but
  second-device/firewall and real remote-control actions remain open.
- Packaged browser dashboard smoke evidence, 2026-05-05:
  `dart run melos run smoke:dashboard-browser:windows` passed. The smoke
  launches the packaged Windows headless executable, opens `/dashboard` in
  headless Chrome through the DevTools protocol, preloads a view token, and
  verifies the rendered dashboard reaches `Connected`, initializes the
  dashboard API client, opens the WebSocket, and renders 6 dashboard panels
  without JavaScript exceptions or `console.error` calls. This caught and fixed
  a packaged dashboard defect where `index.html` referenced `css/dashboard.css`
  and `js/*.js`, which browsers resolved outside `/dashboard` and received
  authenticated JSON 401s instead of static assets. Second-device LAN/firewall
  behavior and mobile remote-client behavior remain open.
- Packaged browser dashboard reconnect smoke evidence, 2026-05-05:
  `dart run melos run smoke:dashboard-reconnect:windows` passed. This runs the
  same packaged dashboard in headless Chrome, kills the packaged headless
  server after the initial dashboard WebSocket connects, waits for the dashboard
  to log `WebSocket disconnected, reconnecting...` with `api.isWsConnected`
  false, restarts the packaged server on the same port, and verifies the page
  logs a second `WebSocket connected` with `api.isWsConnected` true. Mobile
  physical second-device and real remote-control action smoke remain open.
- Packaged authenticated LAN-address smoke evidence, 2026-05-05:
  `dart run melos run smoke:headless-lan:windows` passed. The smoke launches
  the packaged Windows headless executable with admin, view, and control tokens,
  then reaches it through a non-loopback IPv4 URL
  (`http://172.19.96.1:<port>` in the latest run). It verifies public
  `/api/info`, unauthenticated `/api/self-test` rejection, authenticated
  `/api/self-test` with `bindMode=lan` and token auth, view-token rejection on a
  control route, dashboard HTML/CSS/JS serving, and WebSocket `/events`
  ping/pong over the LAN-address URL. A second physical device/browser,
  firewall/router behavior and real remote-control actions remain open.
- Hardware availability probe evidence, 2026-05-05:
  `dart run melos run audit:hardware-availability:windows --no-select` passed
  and generated
  `docs/production-readiness/hardware-availability-probe.json` plus
  `docs/production-readiness/hardware-availability-probe.md`. The probe
  launches the packaged Windows headless executable and discovers required
  public-release hardware classes without connecting to devices. It reported
  `fullRealOrSimulatorCoverage=false` and `fullNonSimulatorCoverage=false`,
  with camera, mount, focuser, guider, and weather candidates present, and no
  real-or-simulator `filterWheel`, `rotator`, `dome`, or `safetyMonitor`
  available on this host. This is blocker evidence only; it does not replace
  command/control smoke.
- Android release build evidence, 2026-05-05:
  `dart run melos run build:mobile:android --no-select` passed and produced
  `apps/mobile/build/app/outputs/flutter-apk/app-release.apk` at 147,298,900
  bytes with SHA256
  `72D1CBCEA03EF496B0C0D2AD03B5D6BDB12041D603067298AE1D0AEA846F4ABF`.
  The mobile app now declares `cupertino_icons`, so the release icon
  tree-shaker no longer reports a missing Cupertino font; it tree-shakes
  Cupertino, Lucide, and Material icon fonts normally.
- Android emulator install/launch smoke evidence, 2026-05-05:
  Installed Android Emulator `36.5.11` and
  `system-images;android-35;google_apis;x86_64`, created disposable AVD
  `nightshade_release_smoke_api35`, installed the release APK with `adb install
  -r`, and launched `com.nightshade.mobile` via `monkey`. The launched app had
  PID `3357`, resumed
  `com.nightshade.mobile/com.example.nightshade_mobile.MainActivity`, and the
  captured log window had no `FATAL EXCEPTION`/`AndroidRuntime` crash entries.
  Screenshot evidence:
  `docs/production-readiness/android-emulator-launch-smoke.png`.
- Android emulator remote-client smoke evidence, 2026-05-05:
  `dart run melos run smoke:mobile-android-remote:windows` passed. The smoke
  starts the rebuilt packaged Windows headless executable on a reserved port
  with admin/view/control tokens, verifies `/api/info` reports API version
  `2.5.0`, verifies unreachable address-specific INDI/Alpaca probes return
  `200 {"devices":[]}` instead of headless `500` responses, installs the
  rebuilt release APK on `emulator-5554`, clears app data and logcat, launches
  `com.nightshade.mobile`, enters `10.0.2.2:<port>` plus the admin token, and
  reaches the connected `Catalog Setup` flow. Log evidence from that clean pass
  shows `NetworkBackend` WebSocket `connected`, no Nightshade auth denial, no
  `Internal server error`, no fatal Android crash signature, no QuickStart
  disposed-ref error, and `AutoDiscovery` completed after caching 10 headless
  devices. Screenshot/XML/log evidence:
  `docs/production-readiness/android-emulator-remote-smoke.png`,
  `docs/production-readiness/mobile-remote-window-connected.xml`, and
  `docs/production-readiness/android-emulator-remote-smoke-log.txt`. This is
  emulator-host-alias evidence, not second-device LAN/firewall evidence, and it
  does not cover real remote-control actions.
- Android emulator remote-client reconnect smoke evidence, 2026-05-05:
  `dart run melos run smoke:mobile-android-reconnect:windows` passed. This uses
  the same packaged Windows headless plus release APK flow as the mobile remote
  smoke, then kills the packaged headless server, restarts it on the same port,
  and verifies the Android client's `NetworkBackend` logs a disconnected state,
  reconnect scheduling, and `WebSocket connected successfully` after restart.
  Reconnect log evidence:
  `docs/production-readiness/android-emulator-remote-reconnect-smoke-log.txt`.
  This is emulator-host-alias evidence, not second-device LAN/firewall
  evidence, and it does not cover real remote-control actions.
- Release documentation evidence, 2026-05-05:
  `docs/headless-secure-setup.md`, `docs/migration-backup-restore.md`,
  `docs/release-notes-template.md`, `docs/known-limitations.md`, and the
  troubleshooting pages for INDI, Alpaca, ASCOM, PHD2, permissions, drivers,
  and firewall have been reviewed against the documentation checklist. They
  provide release-useful coverage, but release notes still need
  candidate-specific evidence and manual QA results before final sign-off.
- Supported hardware matrix evidence, 2026-05-05:
  `docs/supported-hardware-by-platform.md` records backend support by platform,
  device-category expectations, native SDK/vendor packaging caveats, current
  hardware-audit gaps, and the release-gate artifacts that must agree before a
  support claim is published. It is conservative documentation evidence only;
  it does not replace Linux package verification or hardware/control smoke.
- Docs link audit evidence, 2026-05-05:
  `dart run melos run audit:docs-links --no-select` passed and generated
  `docs/production-readiness/docs-link-audit.json` plus
  `docs/production-readiness/docs-link-audit.md`. The audit scanned 116
  Markdown files under `docs/`, checked 144 local links, and found 0 broken
  local links.
- Release docs audit evidence, 2026-05-05:
  `dart run melos run audit:release-docs --no-select` passed and generated
  `docs/production-readiness/release-docs-audit.json` plus
  `docs/production-readiness/release-docs-audit.md`. The audit checks the
  release notes template, known limitations, supported hardware/platform docs,
  installation docs, firewall docs, and migration/backup docs for required
  sections and release traceability links; the current run reports 6 documents
  checked and 0 issues.
- Release PR draft evidence, 2026-05-05:
  `dart run tools/production/release_pr_split_plan.dart` now generates 10
  pathspec files in `docs/production-readiness/release-pr-pathspecs` and 10
  draft PR description files in `docs/production-readiness/release-pr-drafts`.
  It also generates mutually exclusive release decision lists in
  `docs/production-readiness/release-pr-lists`: must ship, generated only,
  binary/evidence, and defer/exclude. The split plan currently assigns 895
  paths, including 323 untracked release-critical paths, across 10 review
  buckets. The decision lists contain 621 must-ship paths, 35 generated-only
  paths, 31 binary/evidence paths, and 208 defer/exclude paths. The
  staged-branch validator still blocks because only 7 index paths are staged
  against the 895-path plan.
- Common troubleshooting guide evidence, 2026-05-05:
  `docs/troubleshooting/common-issues.md` was reviewed for public-release
  scope. It now points users to the support matrix and known limitations before
  treating failures as defects; frames native SDK, Linux, macOS, INDI, Alpaca,
  ASCOM, PHD2, runtime dependency, and save-path troubleshooting as
  release-/capability-dependent; and links users to driver, permissions, and
  firewall troubleshooting for backend-specific checks. A local Markdown link
  check for that file found all local targets present.
- First imaging run guide evidence, 2026-05-05:
  `docs/getting-started/first-image.md` was reviewed for public-release scope.
  It now points first-run users to supported hardware, known limitations, and
  migration/backup guidance; avoids assuming unsupported driver capabilities;
  warns that disabled controls should be recorded rather than bypassed during
  release smoke; and links remote/headless users to the secure setup guide. A
  local Markdown link check for that file found all local targets present.
- First device connection guide evidence, 2026-05-05:
  `docs/getting-started/first-connection.md` was reviewed for public-release
  scope. It now points users to supported hardware, known limitations, and
  migration/backup guidance before connection work; frames ASCOM, Native,
  Alpaca, INDI, filter wheel, guiding, and simulator behavior as
  release- and capability-dependent; adds safer mount-control checks; and links
  remote/headless users to secure setup only after local hardware behavior is
  verified. A local Markdown link check for that file found all local targets
  present.
- Installation and docs index scope evidence, 2026-05-05:
  `docs/index.md` and `docs/getting-started/installation.md` were reviewed for
  public-release claims. They now tie platform support, mobile/remote behavior,
  updates, macOS/Linux package examples, and installation instructions to the
  completed release notes, support matrix, and verified artifacts instead of
  implying that every platform package or remote mode is automatically shipped.
  Focused local Markdown link checks for both files passed.
- Fail-closed audit evidence, 2026-05-05:
  `dart run melos run audit:fail-closed` passed with
  `Fail-closed policy checks passed.` It generated
  `docs/production-readiness/fail-closed-audit.json` plus
  `docs/production-readiness/fail-closed-audit.md`; the public release gate now
  consumes the JSON artifact and reports 0 violations.
- UI consistency structured audit evidence, 2026-05-05:
  `dart run melos run audit:ui-consistency --no-select` passed and generated
  `.ui_consistency_audit.txt` plus
  `docs/production-readiness/ui-consistency-audit.json`. It reports 203 total
  findings, 0 blocking findings, 0 raw button style findings, 0 large-radius
  findings, 0 empty callbacks, 0 unadvertised headless routes, 0 semantic raw
  Material color findings, and 203 intentional image/overlay color findings.
- Oversized file audit evidence, 2026-05-05:
  `dart run melos run audit:oversized-files --no-select` passed and generated
  `docs/production-readiness/oversized-file-audit.json` plus
  `docs/production-readiness/oversized-file-audit.md`. It scanned 705
  hand-authored Dart files, found 65 warning-sized files at 1000+ lines, and
  found 16 critical-sized files at 2500+ lines. This is a planning audit for
  future refactors; it does not replace focused tests or block the release
  gate by itself.
- Developer quality rollup evidence, 2026-05-05:
  `dart run melos run audit:developer-quality --no-select` passed and
  generated `docs/production-readiness/developer-quality-audit.json` plus
  `docs/production-readiness/developer-quality-audit.md`. The rollup consumes
  UI consistency, headless route policy, headless response helper, and
  oversized-file audit artifacts. It currently reports 0 issues, 0 UI blocking
  findings, 0 headless route policy issues, 0 headless response helper issues,
  10 raw headless `Response.*` calls, all classified as intentional non-JSON
  stream/static/attachment/preflight responses, 0 unclassified raw responses,
  724 typed JSON helper calls, and 16 critical oversized files tracked as
  non-blocking planning risk.
- Linux release workflow automation evidence, 2026-05-05:
  `dart run melos run audit:linux-release-workflow --no-select` passed and
  generated `docs/production-readiness/linux-release-workflow-audit.json` plus
  `docs/production-readiness/linux-release-workflow-audit.md`. It verifies
  `.github/workflows/linux-release-build.yml` still runs on Ubuntu, builds the
  Linux desktop bundle, invokes the package metadata/hash generator, and
  uploads both package and metadata artifacts. This is automation evidence
  only; it does not replace a successful Linux workflow run or runtime smoke.
- Windows bundle structured audit evidence, 2026-05-05:
  `dart run melos run audit:windows-bundle --no-select` passed and generated
  `docs/production-readiness/windows-bundle-audit.json` plus
  `docs/production-readiness/windows-bundle-audit.md`. It scanned 57 files
  under `apps/desktop/build/windows/x64/runner/Release`, found 0 missing
  required files, and found 0 disallowed files.
- Dependency hygiene evidence, 2026-05-05:
  `dart run melos run audit:dependency-hygiene --no-select` passed and
  generated `docs/production-readiness/dependency-hygiene.json` plus
  `docs/production-readiness/dependency-hygiene.md`. It scanned 10 workspace
  packages, compared each package `lib/` `package:` imports against direct
  pubspec declarations, and found 0 missing direct dependencies. The public
  release gate now consumes this JSON artifact.
- Headless API contract evidence, 2026-05-05:
  `dart run melos run audit:headless-api-contract --no-select` passed and
  generated `docs/production-readiness/headless-api-contract-audit.json` plus
  `docs/production-readiness/headless-api-contract-audit.md`. It reports 295
  registered routes, 295 advertised routes, 293 advertised HTTP routes, 270
  generated OpenAPI paths, 255 `NetworkBackend` routes, and zero drift between
  route registration, `/api/info`, generated OpenAPI coverage, and
  `NetworkBackend` call sites. Focused verification:
  `flutter test test/headless_api/network_backend_contract_test.dart` passed in
  `apps/desktop`.
- Headless route policy evidence, 2026-05-05:
  `dart run melos run audit:headless-route-policy --no-select` passed and
  generated `docs/production-readiness/headless-route-policy-audit.json` plus
  `docs/production-readiness/headless-route-policy-audit.md`. It reports 0
  policy issues, 19 high-risk route policies, 9 default-limited control route
  policies, `/api/files/browse` audit action `file_browse`, and no rate limit
  on `/api/info`. Focused verification:
  `flutter test test/headless_api/route_metadata_test.dart` passed in
  `apps/desktop`.
- Headless response helper evidence, 2026-05-06:
  `dart run tools/production/headless_response_helper_audit.dart` passed and
  generated `docs/production-readiness/headless-response-helper-audit.json`
  plus `docs/production-readiness/headless-response-helper-audit.md`. The audit
  verifies typed JSON response helpers and unit coverage are present, and
  tracks 10 raw headless `Response.*` calls, 10 intentional raw responses, 0
  unclassified raw responses, 5 JSON content-type mentions, 25 helper imports,
  and 724 typed JSON helper calls as route-by-route migration debt and adoption
  evidence. The remaining raw responses are classified as stream, attachment,
  static-file, or empty preflight responses rather than JSON helper debt.
  Focused verification:
  `dart run tools/production/headless_response_helper_audit_self_test.dart`;
  `dart run tools/production/developer_quality_audit_self_test.dart`;
  `flutter test test/headless_api/auth_middleware_test.dart`;
  `flutter test test/headless_api/network_backend_contract_test.dart`;
  `flutter test test/headless_api/route_metadata_test.dart`;
  `flutter test test/headless_api/device_handlers_test.dart`;
  `flutter test test/headless_api/scheduler_handlers_test.dart`;
  `flutter test test/headless_api/planetarium_handlers_test.dart`;
  `flutter test test/headless_api/science_handlers_test.dart`;
  `flutter test test/headless_api/focus_model_handlers_test.dart`;
  `flutter test test/headless_api/analytics_handlers_test.dart`;
  `flutter test test/headless_api/sequence_management_handlers_test.dart`;
  `flutter test test/headless_api/safety_monitor_handlers_test.dart`;
  `flutter test test/headless_api/framing_handlers_test.dart`;
  `flutter test test/headless_api/imaging_handlers_test.dart`;
  `flutter test test/headless_api/transient_handlers_test.dart`;
  `flutter test test/headless_api/suggestion_handlers_test.dart`;
  `flutter test test/headless_api/backup_handlers_test.dart`;
  `flutter test test/headless_api/weather_handlers_test.dart`;
  `flutter test test/headless_api/target_handlers_test.dart`;
  `flutter test test/headless_api/session_handlers_test.dart`;
  `flutter test test/headless_api/profile_handlers_test.dart test/headless_api/sequencer_handlers_test.dart test/headless_api/guiding_handlers_test.dart test/headless_api/flat_wizard_handlers_test.dart test/headless_api/equipment_handlers_test.dart test/headless_api/mosaic_handlers_test.dart test/headless_api/auxiliary_handlers_test.dart test/headless_api/filesystem_handlers_test.dart test/headless_api/response_helpers_test.dart`
  passed in `apps/desktop`.
- Headless request correlation evidence, 2026-05-05:
  `NetworkBackend` and the web dashboard now send `x-request-id` on API
  requests, and the server CORS policy allows `X-Request-ID`. Focused
  verification: `flutter test test/headless_api/auth_middleware_test.dart`
  passed in `apps/desktop`, including coverage that `/api/info` and protected
  auth errors preserve caller-supplied request IDs in response headers.
- Placeholder audit evidence, 2026-05-05:
  `dart run melos run audit:placeholders` passed. The audit reported 9 known
  runtime marker hits, 0 high-risk hits, and no new high-risk markers compared
  to `docs/production-readiness/highrisk-baseline.txt`.
- Public release gate evidence, 2026-05-05:
  `dart run melos run audit:public-release-gate --no-select` passed and
  generated `docs/production-readiness/public-release-gate.json` plus
  `docs/production-readiness/public-release-gate.md`. The gate is conservative:
  it treats missing direct evidence as a blocker and does not accept proxy
  signals as completion. Current result is `NOT_READY`, with pass evidence for
  production analyzer, placeholder audit, fail-closed policy, UI consistency,
  developer quality, Windows bundle, dependency hygiene, headless API contract,
  headless route policy, headless response helpers, docs local links, release
  docs, public release verifier self-tests, Linux release workflow automation,
  synthetic migration regression coverage, Android emulator remote smoke, and
  Android emulator reconnect smoke, and blockers for
  release staging, Linux release build/package evidence,
  hardware/control smoke,
  older-profile migration, second-device LAN/firewall smoke, real
  remote-control actions, and final checklist sign-off.
- Public release gate self-test, 2026-05-05:
  `dart run melos run audit:public-release-gate:self-test --no-select` passed
  against temporary fixtures. The self-test verifies the gate rejects a failed
  aggregate verifier self-test artifact, rejects a stale release PR split plan
  whose `sourceGeneratedAt`, path set, and entry count no longer match the
  staging audit, and verifies the gate can report `READY` when all required
  evidence fixtures are complete.
- Release staging and PR split plan self-test, 2026-05-05:
  `dart run melos run audit:release-staging-pr-plan:self-test --no-select`
  passed against a temporary dirty git fixture. The self-test verifies staging
  classification for modified, deleted, generated, binary, release-critical,
  and out-of-release-scope paths; verifies dirty/untracked-critical fail modes;
  verifies stale pathspec cleanup; and verifies the PR split plan assigns every
  staging-audit path to exactly one bucket with matching pathspec file content.
- Public release self-test aggregate, 2026-05-05:
  `dart run melos run audit:public-release-self-tests --no-select` passed and
  ran all 15 release verifier self-tests: public release gate, blocker inputs,
  external evidence verifier, completion audit, owner checklist, checklist
  audit, release staging/PR split plan coverage, release PR owner matrix, Linux
  package metadata, Linux workflow audit, oversized-file audit, developer
  quality audit, headless response helper audit, migration regression audit,
  and release docs audit. It wrote
  `docs/production-readiness/public-release-self-tests.json` plus
  `docs/production-readiness/public-release-self-tests.md`, recording 15 passed
  scripts, 0 failed scripts, exit codes, and per-script durations.
- External evidence verifier self-test, 2026-05-05:
  `dart run melos run audit:public-release-external-evidence:self-test --no-select`
  passed. The self-test runs the external evidence verifier against temporary
  fixtures and verifies it rejects missing evidence, accepts Linux artifact
  evidence only when file size and SHA256 match, rejects localhost-style LAN
  smoke evidence, rejects physical-LAN evidence without WebSocket reconnect
  observation, accepts a valid physical-LAN evidence fixture, rejects incomplete
  hardware and remote-control command fixtures that lack state readback, device
  coverage, or real/simulator backing type, accepts valid hardware and
  remote-control fixtures, rejects template/incomplete final sign-off evidence,
  and accepts a valid final sign-off fixture with completed checklist audit and
  release notes.
- Public release blocker input evidence, 2026-05-05:
  `dart run melos run audit:public-release-blocker-inputs --no-select` passed
  and generated `docs/production-readiness/public-release-blocker-inputs.json`
  plus `docs/production-readiness/public-release-blocker-inputs.md`. It maps
  each current gate blocker to required owner input, acceptance criteria, rerun
  commands, and expected evidence. This artifact is an input checklist only: it
  does not satisfy the blockers without the corresponding external evidence.
- Public release blocker input self-test, 2026-05-05:
  `dart run melos run audit:public-release-blocker-inputs:self-test --no-select`
  passed against temporary blocked and ready fixtures. The self-test verifies
  all seven current public-release blocker IDs produce non-empty required
  inputs, acceptance criteria, rerun commands, expected evidence, and current
  gate detail, and verifies a ready gate produces zero blocker-input records.
- Public release checklist audit, 2026-05-05:
  `dart run melos run audit:public-release-checklist --no-select` passed and
  generated `docs/production-readiness/public-release-checklist-audit.json`
  plus `docs/production-readiness/public-release-checklist-audit.md`. It
  reports 284 checklist items, 0 checked items, 284 unchecked items, 0 checked
  items without evidence notes, and confirms the checklist references
  `docs/known-limitations.md` and
  `docs/supported-hardware-by-platform.md`. This is status evidence only; it
  does not provide final sign-off.
- Public release checklist audit self-test, 2026-05-05:
  `dart run melos run audit:public-release-checklist:self-test --no-select`
  passed against temporary blocked and complete checklist fixtures. The
  self-test verifies item counts, checked-without-evidence detection,
  known-limitations and supported-hardware reference detection, and
  `--fail-on-unchecked` behavior for both blocked and complete checklists.
- Public release external evidence verifier, 2026-05-05:
  `dart run melos run audit:public-release-external-evidence --no-select`
  passed and generated
  `docs/production-readiness/public-release-external-evidence.json` plus
  `docs/production-readiness/public-release-external-evidence.md`, along with
  evidence templates under
  `docs/production-readiness/external-evidence-templates/`. The verifier is the
  schema gate for future Linux build, full hardware/control, second-device LAN,
  real remote-control, and final sign-off evidence. The full hardware/control
  schema now requires command results to include every required device type,
  successful command status, state readback, and real/simulator backing type.
  The second-device LAN schema requires WebSocket reconnect observation. The
  verifier also rejects evidence unless referenced files exist: Linux package
  size/SHA256 must match the artifact, Linux runtime smoke logs must exist,
  hardware smoke logs must exist, second-device screenshots/logs must exist,
  real-control audit logs must exist, and final sign-off must name the current
  git HEAD, include a non-empty release notes artifact, and match a checklist
  audit with zero unchecked or checked-without-evidence items. Release notes
  must not point to the template, must include the required release-note
  sections, must reference the support/limitations/gate artifacts, and must not
  contain unreplaced template placeholders. Current result is 0 of 5 external checks passing
  because no completed external evidence files have been supplied.
- Public release completion audit, 2026-05-05:
  `dart run melos run audit:public-release-completion --no-select` passed and
  generated `docs/production-readiness/public-release-completion-audit.json`
  plus `docs/production-readiness/public-release-completion-audit.md`. It maps
  each explicit P0 requirement from `goal.txt` to concrete evidence, verifier
  coverage, and remaining gaps. Current completion decision is
  `NOT_ACHIEVED`, with 0 complete P0 checks and 7 blocked or incomplete P0
  checks.
- Public release completion audit self-test, 2026-05-05:
  `dart run melos run audit:public-release-completion:self-test --no-select`
  passed against temporary blocked and achieved fixtures. The self-test verifies
  the completion audit reports `decision=NOT_ACHIEVED` separately from
  `gateDecision=NOT_READY` for blocked fixtures, can report `decision=ACHIEVED`
  when all P0 gate evidence is complete, and marks the
  generated/binary/native split requirement complete only after the release
  staging gate has passed with a split-plan artifact present.
- Release staging audit evidence, 2026-05-05:
  `dart run tools/production/release_staging_audit.dart` passed and generated
  `docs/production-readiness/release-staging-audit.json` plus
  `docs/production-readiness/release-staging-audit.md`. The report classifies
  the current `main` worktree at `bbdee9b` into 895 changed/untracked entries across review
  buckets such as
  `headless-remote`, `native-rust`, `app-ui`, `generated`,
  `binary-native-artifact`, `release-evidence-docs`, and `release-tooling`.
  It is blocker evidence only: the report shows the worktree is still broad
  and dirty, with 323 untracked release-critical entries that must be staged
  or explicitly excluded before a clean release branch/PR can be considered
  ready.
- Release PR split plan evidence, 2026-05-05:
  `dart run tools/production/release_pr_split_plan.dart` passed and generated
  `docs/production-readiness/release-pr-split-plan.json` plus
  `docs/production-readiness/release-pr-split-plan.md`. The plan assigns every
  non-deleted dirty path from the staging audit into proposed review buckets for generated
  files, binary/evidence artifacts, release infrastructure/evidence,
  headless remote API/dashboard, mobile remote client, native driver/bridge
  source, core data/services, desktop UI/workflows, tests/support tooling, and
  out-of-release-scope review. It also writes exact bucket pathspec files under
  `docs/production-readiness/release-pr-pathspecs/` and records matching
  `git add --pathspec-from-file=...` commands for use on a clean release branch.
  The public release gate now validates this coverage directly; the current
  gate reports 10 pathspec files, 895 pathspec lines, 895 unique paths, and
  exact coverage between the staging audit, split-plan JSON, and pathspec files.
  This is still planning evidence only: it does not stage files, create a
  non-main branch, create a PR, or satisfy the clean release branch gate.
- Workspace test evidence, 2026-05-05:
  `dart run melos run test --no-select` passed across 10 Flutter packages. The
  `test` Melos script now uses the local Melos entrypoint instead of requiring
  a globally installed `melos`, and `packages/nightshade_updater/pubspec.yaml`
  now declares `uses-material-design: true` so its tests no longer emit Flutter
  Material Design package-configuration errors. The latest sweep includes the
  dashboard static-asset serving regression test.
- `git diff --check` on the touched UI audit files produced no whitespace
  errors; it emitted only Git LF-to-CRLF working-copy warnings.

## Historical April Audit Context

The section below records an earlier audit pass from 2026-04-03 at
`bbdee9bd7248d5fbced9e521c1ed69c465f7f13f`. Treat it as historical evidence,
not as the current ship decision.

## Evidence Collected

- Static gates:
  - `dart run melos run analyze:production` -> `Production: errors=0, warnings=0`
  - `dart run melos run audit:fail-closed` -> passed
  - `dart run melos run audit:placeholders` -> passed
- Automated tests:
  - `flutter test` in `packages/nightshade_app` -> passed
  - `flutter test` in `packages/nightshade_plugins` -> passed
  - `flutter test` in `packages/nightshade_webrtc` -> passed
- Targeted code review completed on:
  - router and shell/navigation
  - settings shell, remote access, and pairing
  - planner
  - diagnostics
  - equipment connections/profile surfaces

## Resolved Findings

1. Mobile navigation now uses a production mobile IA instead of a horizontal scrolling strip.
   Evidence: [nightshade_bottom_navigation.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/shell/widgets/nightshade_bottom_navigation.dart) now exposes four primary tabs plus a `More` sheet, and [app_shell.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/shell/app_shell.dart) now routes mobile state off the current route instead of the old index assumptions.

2. The public Equipment debug surface is no longer reachable from the release UI.
   Evidence: the debug action wiring was removed from [connections_tab.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart), so the broken debug dialog is no longer exposed to end users.

3. Pairing failures are now surfaced to the user.
   Evidence: [pairing_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/settings/pairing_screen.dart) now renders a visible error banner, supports dismissing error state, and uses stable error keys instead of silently swallowing failures.

4. Remote Access port changes now persist reliably without submit-only behavior.
   Evidence: [remote_access_settings.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/settings/widgets/remote_access_settings.dart) now commits on blur and tap-outside, keeps the field synchronized with persisted settings, and restores the prior value with feedback on invalid input.

5. Planner, Diagnostics, and Equipment no longer dump raw internal errors to the user in the audited release paths.
   Evidence:
   - [planner_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/planner/planner_screen.dart) now shows designed error states and recovery actions
   - [diagnostics_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/diagnostics/diagnostics_screen.dart) now shows generic failure copy plus retry actions
   - [profiles_tab.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/equipment/tabs/profiles_tab.dart) and [connections_tab.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/equipment/tabs/connections_tab.dart) now use user-facing messages instead of exception dumps in the audited error paths

6. The new shell/settings/planner/diagnostics release surfaces are materially more localization-safe.
   Evidence:
   - [side_navigation.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/shell/widgets/side_navigation.dart)
   - [settings_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/settings/settings_screen.dart)
   - [remote_access_settings.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/settings/widgets/remote_access_settings.dart)
   - [planner_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/planner/planner_screen.dart)
   - [diagnostics_screen.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/screens/diagnostics/diagnostics_screen.dart)
   - [nightshade_localizations.dart](/C:/Users/scdou/Documents/Nightshade2/packages/nightshade_app/lib/localization/nightshade_localizations.dart)

## Area Status

### Global Gates

Status: pass

Conclusion:
- no production errors or production warnings
- placeholder and fail-closed audits are green
- targeted app/plugin/webrtc tests pass

### Shell, Routing, Navigation

Status: pass in audited scope

Conclusion:
- desktop shell remains structurally coherent
- mobile navigation is now release-appropriate for the audited routes

### Settings / Remote Access / Pairing

Status: pass in audited scope

Conclusion:
- remote access lifecycle/security path remains materially improved
- pairing and remote-access settings now have user-visible failure handling and better persistence behavior

### Planner

Status: pass in audited scope

Conclusion:
- success/loading/error/empty states are coherent
- the audited user-facing copy and action labels are at release quality

### Diagnostics

Status: pass in audited scope

Conclusion:
- the earlier session-selection edge case remains fixed
- the audited error handling and user-facing labels are at release quality

### Equipment

Status: pass in audited scope

Conclusion:
- the public debug leak is removed
- the audited profile/connection error paths no longer expose internals

## Remaining Caveats

These are not current code blockers from this audit pass, but they still matter for an actual public release sign-off:

- The overall branch is still extremely broad and dirty. A public tag should be cut from an intentionally staged release candidate, not from a loosely scoped worktree with many unrelated modified/generated files.
- The sections below were not deeply re-exercised end to end with real hardware in this pass and should remain open in the master checklist until manually verified:
  - dashboard behavior under realistic live hardware load
  - imaging end-to-end capture and save-path behavior
  - focus/autofocus with real devices
  - guiding/PHD2 interactions and sequencer coupling
  - planetarium interaction/performance with realistic catalogs
  - weather/safety operational fail modes
  - flat wizard, framing, polar alignment, and other utility workflows
  - observation log and observing list flows
  - updater/release delivery UX
  - extended manual QA across desktop and mobile breakpoints

## Release Recommendation

Historical April conclusion: from the concrete issues found in that audit pass,
the branch was considered shippable in the audited scope.

Current May 5 conclusion: the local worktree is not release-ready. The current
ship decision remains blocked by the P0 evidence gaps listed at the top of this
report.

Before pushing a public release, do the final process pass:

1. Stage only the intended release set on a clean release branch/PR.
2. Run the green gates on that exact release candidate.
3. Perform Linux packaging verification on Linux.
4. Perform manual or simulator-backed hardware smoke across the still-open
   hardware/user-journey areas above.
5. Record migration, headless/mobile/dashboard/WebSocket, and known-unsupported
   platform evidence in the master checklist before final sign-off.
