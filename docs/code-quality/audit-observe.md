# CQ-AUDIT-OBSERVE — Cross-Cutting Observability + Error-Handling Audit

- **Branch:** `worktree-agent-ac0decebaa1ca0d2c`
- **Base SHA:** `bbdee9b` ("fixed a ton of bugs")
- **Version:** 2.5.0
- **Scope:** read-only audit; no source files modified.

---

## Status (as of v2.5.x hardening, 2026-05-16)

The original audit below is preserved verbatim for context. This banner
tracks what landed in the v2.5.x code-quality hardening cycle
(see `CHANGELOG.md` and `v2.5.x-roadmap.md`).

### CRITICAL — Resolved

- **§1a — `NightshadeException._parseJson` dead code.** Now actually
  `jsonDecode`s the FFI `ErrorInfo` payload instead of unconditionally
  returning `null`; every typed Rust error survives across the boundary
  with `device_id`, `error_code`, `is_recoverable`, and
  `should_reconnect` intact. Resolved via `CQ-W1-PARSEJSON`.
- **§6a — 13 fail-closed handler violations**
  (`handlers_e_tostring` + `handlers_status_failed_string` across
  `auxiliary`, `flat_wizard`, `backup`, `mosaic`, `science`, `device`
  handlers). Resolved via `CQ-W1-FAILCLOSED`. The all-sky polar-align
  `ffi_backend:2064 UnimplementedError` fail-closed gap resolved via
  `CQ-W9-FAIL-CLOSED-ALLSKY`.

### HIGH — Resolved

- **§9 — Operational runbook gap.** New `RUNBOOK.md` covering frozen
  startup, plate-solve failures, OTA rollback, sequence-resume, and
  headless-unreachable scenarios via `CQ-W6-RUNBOOK`.
- **§2b — 477 `print` / `debugPrint` calls across 61 files.** Top-10
  hot paths migrated to `LoggingService`: `apps/desktop/lib/main.dart`
  (134) via `CQ-W2-PRINT`, `bridge_stub.dart` (103) +
  `catalog_manager.dart` (37) via `CQ-W6-PRINT-FULL`,
  `network_backend.dart` (32) + `auto_save_service.dart` (21) via
  `CQ-W6-PRINT-FULL:core-services`, `quick_start_checker` + mobile
  services via `CQ-W6-PRINT-FULL:quick-start-mobile`, and the
  remaining ~232 sites via `CQ-W11-PRINT-FULL:final`.
- **§1c — 15+ Dart `catch (_)` swallows** in `enhanced_discovery.dart`,
  `plate_solver_utils.dart`, `coordinate_parser.dart`,
  `network_backend.dart`, `star_catalog.dart`, `satellite_catalog.dart`,
  `logging_service.dart`. Audited and either logged via
  `dart:developer` or annotated with `// Why:` rationale via
  `CQ-W6-CATCH-UNDERSCORE` and `:2`.

### MED — Resolved

- **§2e — Bearer token redaction.** `main_headless.dart` startup
  banner now redacts the token to `<first-4>…<last-4>` via
  `CQ-W1-TOKEN-REDACT`.
- **§4c — Diagnostic dump.** New service + screen bundles logs +
  active profile + sequence state + system info into a single zip
  via `CQ-W6-DIAG-DUMP`.
- **§8b — SQLite corruption recovery.** Drift `integrity_check` +
  backup-and-recreate path with first-launch UI marker via
  `CQ-W6-SQLITE-RECOVERY`.
- **§8c — Background-service supervision.** 5 long-running futures
  wrapped in supervised wrappers via `CQ-W6-SUPERVISION`.
- **§10 — Behavioral markers** registered + audited across updater,
  webrtc, planetarium, ui, plugins, core, app, apps, and native
  crates via `CQ-W9-BEHAVIORAL-MARKERS`, `CQ-W10-BEHAVIORAL-MARKERS:A`,
  `:B`, and `CQ-W11-BEHAVIORAL-MARKERS:C`.

### Remaining (deferred to v2.6 or later)

- **§3d — Localization.** 0 of 35 `NightshadeError` Display strings
  localized; full i18n is v3.x scope.
- **§4a / §4b — Telemetry / opt-in crash uploader.** Out-of-scope
  per local-first ethos; the new diagnostic-dump screen and runbook
  are the agreed substitute for v2.5.x.
- **§6b — Missing fail-closed rules for scheduler / NINA import /
  defect-map paths.** Tracked but not added in this cycle; existing
  gate is operational and W1 closed the 13 known violations.
- **§2d — Log-level discipline in vendor SDK modules** (`info!` →
  `debug!` for routine I/O). Low priority.

---

## 1. Error-handling consistency across the FFI boundary

### a) FFI error preservation — sampled paths

`NightshadeError` is well-modeled in `native/nightshade_native/bridge/src/error.rs:24-214` with 35 variants and a structured JSON-over-FFI `ErrorInfo` envelope (`error.rs:725-758`). Dart side mirrors via `NightshadeException` (`packages/nightshade_core/lib/src/backend/nightshade_exception.dart:13-75`).

**Severe regression — JSON envelope never decodes:** `nightshade_exception.dart:98-106` `_parseJson()` is a hard-coded `return null;` with a comment "Let the caller handle JSON parsing" — but no caller does, and `NightshadeException.fromError()` at line 84 calls `_parseJson` directly. Result: every Rust-side `to_json()` payload falls through to the string-heuristic classifier and loses `device_id`, `error_code`, `is_recoverable`, `should_reconnect`, and the precise `category`. **CRITICAL (HIGH)** — this silently degrades all FFI error fidelity. Investment in the Rust `ErrorInfo` machinery is wasted.

Sampled paths (10):

| Path | Result | Notes |
|---|---|---|
| Camera expose → `ffi_backend.dart:2482` | "Operation failed: …" wrapper | message survives but type info lost |
| Mount slew | passes through `NightshadeError::Display` | message survives |
| Plate solve (`plate_solve_service.dart:148`) | `"ASTAP failed: <stderr>"` | actionable |
| Defect-map build | OK | typed error preserved string-wise |
| Sequence start | `Result<NightshadeError>` propagates | OK |
| Autofocus (`indi/src/autofocus.rs`) | tracing + error returned | OK |
| Filter wheel change | OK | structured |
| Backup handler `e.toString()` | leaks runtime type | violates fail-closed rule (see §6) |
| Discovery (INDI) | OK | typed |
| Connect device | typed | OK |

### b) `NightshadeError` variant distribution

35 variants total (`error.rs`). Roughly: **6 connection**, **4 hardware**, **3 timeout**, **4 validation**, **3 operation**, **6 imaging**, **3 I/O+seq**, **5 driver-specific**, **5 system**. Healthy distribution — `Internal(String)` and `OperationFailed(String)` are catch-alls but the From-impls and `with_context` extension trait at `error.rs:809-827` route into them deliberately, not lazily. No single variant dominates.

### c) Dart catch-and-downgrade patterns

Top swallows of typed exceptions to `null/false/[]`:

1. `packages/nightshade_webrtc/lib/src/enhanced_discovery.dart:511-512` `catch(_) → return null`
2. `packages/nightshade_webrtc/lib/src/enhanced_discovery.dart:565-566` `catch(_) → return false`
3. `packages/nightshade_planetarium/lib/src/catalogs/star_catalog.dart:72-74` (logs + returns `[]`)
4. `packages/nightshade_core/lib/src/utils/plate_solver_utils.dart:248-250` (silent path-fail)
5. `packages/nightshade_core/lib/src/utils/plate_solver_utils.dart:353-355` (silent path-fail)
6. `packages/nightshade_core/lib/src/utils/coordinate_parser.dart:67-68, 118-119` (silent)
7. `packages/nightshade_core/lib/src/backend/network_backend.dart:169-171`
8. `packages/nightshade_planetarium/lib/src/catalogs/satellite_catalog.dart:254-256`
9. `packages/nightshade_core/lib/src/backend/nightshade_exception.dart:103-104` (in JSON-parse dead code, see §1a)
10. `packages/nightshade_core/lib/src/services/logging_service.dart:230-232, 297-299` (export silently returns `[]/0`)
11. `packages/nightshade_bridge/lib/src/bridge_stub.dart` — many `catch (_) {}` blocks
12. `packages/nightshade_bridge/lib/src/alpaca_client.dart` — empty catches
13. `packages/nightshade_app/lib/app.dart` (one)
14. `packages/nightshade_core/lib/src/services/catalog_service.dart`
15. `packages/nightshade_core/lib/src/services/transient_alert_service.dart`

The CLAUDE.md doctrine "Errors are a feature. Silent fallbacks hide bugs for months." is materially violated in the `plate_solver_utils`, `coordinate_parser`, and `enhanced_discovery` paths. **HIGH**.

---

## 2. Logging discipline

### a) `LoggingService` surface

`packages/nightshade_core/lib/src/services/logging_service.dart`: 5 levels (debug/info/warning/error/critical), in-memory ring buffer of 1000 entries (`:73`), forwards to `dart:developer.log` with severity mapping (`:165-184`), file export at `:246-278`, native bridge initialised with directory (`:114`). Sound design.

### b) Direct `print()` / `debugPrint()` in non-test code

**477 occurrences across 61 files** (Grep, glob `**/lib/**/*.dart`). High-volume offenders:

| File | Count |
|---|---|
| `packages/nightshade_bridge/lib/src/bridge_stub.dart` | 103 |
| `packages/nightshade_planetarium/lib/src/catalogs/catalog_manager.dart` | 37 |
| `packages/nightshade_core/lib/src/backend/network_backend.dart` | 32 |
| `apps/desktop/lib/main.dart` | 18 |
| `apps/desktop/lib/main_headless.dart` | 25 |
| `apps/desktop/lib/widgets/update_manager.dart` | 8 |
| `apps/mobile/lib/services/network_service.dart` | 18 |
| `packages/nightshade_planetarium/lib/src/catalogs/satellite_catalog.dart` | 10 |
| `packages/nightshade_core/lib/src/services/auto_save_service.dart` | 21 |
| `packages/nightshade_app/lib/widgets/quick_start_checker.dart` | 17 |

Some are bootstrap-stage (`main.dart` prints before `LoggingService` initialised — defensible), but the planetarium catalogs and `bridge_stub.dart` are runtime-hot paths that bypass log levels, file rotation, and the export pipeline. **MED**.

### c) Rust `tracing` vs `println!`/`eprintln!`

Healthy ratio: **1569 tracing macros across 70 files** vs **238 `println!`/`eprintln!` across 12 files**. The println cluster is in `updater/src/main.rs` (CLI), `bridge/src/lib.rs:7` (panic hook fallback), and `examples/`/`build.rs` — all legitimate. No production-path `println!` regressions detected.

### d) Logging level discipline

Sample of `executor.rs`: uses `info!` for state transitions, `warn!` for retries, `error!` for failures, `debug!` for checkpoint cadence — consistent. Vendor SDK modules (`vendor/zwo.rs`, `vendor/qhy.rs`) lean on `info!` for routine I/O which would benefit from `debug!` to avoid log-volume regressions in long sessions. **LOW**.

### e) Sensitive data in logs

Spot-checked log call sites for tokens/passwords/credentials — **no matches**. Token CLI args are echoed once at headless startup to `_logInfo` in `main_headless.dart:236` ("Authorization: Bearer <token>"). This is the operator console at boot; defensible but means the log file rotates with the token in plaintext. **MED** — recommend redacting to `Bearer <first-4>…<last-4>`.

---

## 3. User-facing error UX

### a) Surface patterns

`SnackBar` and `showDialog` are the dominant patterns. `packages/nightshade_app/lib/utils/snackbar_helper.dart` centralizes positive/error toasts. Inline banners exist in equipment screen. Status text used for transient device states. Silent swallow (BAD) occurs in the `catch(_)` paths catalogued in §1c — primarily catalog-loading and coordinate-parsing paths where the user sees an empty list rather than an error reason.

### b) Sample 10 operations

| Operation | Pattern |
|---|---|
| Camera connect | SnackBar (equipment screen) |
| Mount slew failure | SnackBar via device_connection_mixin |
| Plate solve fail | dialog + error in capture panel |
| Sequence start error | SnackBar + status bar |
| Profile save | SnackBar |
| Backup restore | SnackBar |
| ASCOM driver error | SnackBar with HRESULT (good) |
| Catalog load failure | **silent** (empty list shown) |
| Coordinate parse | **silent** (input field rejects) |
| WebRTC discovery fail | **silent** |

Pattern is inconsistent but the dominant SnackBar+dialog model is fine. The silent paths are the gap.

### c) Actionability

Most error strings are technical. Examples:
- Good: `"ASTAP failed: <stderr>"` (`plate_solve_service.dart:148`) — surfaces solver output.
- Good: `NightshadeError::user_message()` — produces `"<device> does not support: <op>"`, `"Hardware error on '<id>': <msg>"`.
- Weak: `"Operation failed: <msg>"` (`ffi_backend.dart:2482`) — composite wrapper that adds no actionable info.
- Weak: bare `"Connection test failed: $e"` (`network_backend.dart:170`) — no remediation hint.

### d) Localization

`nightshade_localizations.dart` exists but error strings are predominantly hard-coded English. Rough audit: of the 35 `NightshadeError` Display strings, **0 are localized**. SnackBar/dialog content largely uses literal strings, not ARB keys. For a v2.5.0 desktop product this is acceptable; flag as **LOW** for international rollout.

---

## 4. Observability / telemetry

### a) Telemetry presence

Grep for `sentry`, `firebase_crashlytics`, `mixpanel`, `amplitude`, `posthog` — **zero hits**. Only matches for "telemetry" are inline comments about cooler/camera telemetry (`imaging_screen.dart:4000`), not analytics. **The app collects no remote telemetry, crash reports, or active-user metrics.**

### b) Sensible minimal observability for a desktop-first astrophotography app

Honest assessment:
- **Opt-in only.** Local-first astrophotographers explicitly reject cloud beacons.
- **Crash reporting** is the most defensible addition: the Rust panic hook (`bridge/src/lib.rs:197`) already logs to disk; bundling a "Send anonymized crash report" button in the existing log viewer that POSTs to a self-hosted Sentry would satisfy the maintainer need without violating the ethos.
- **Metrics that are safe by construction:** anonymous aggregates like "ASTAP vs Astrometry.net solve success rate" sent only when the user clicks "Improve Nightshade." Never device IDs, file paths, or coordinates.

### c) Local diagnostic dumps

`LoggingService.exportLogs()` (`logging_service.dart:246-278`) concatenates rotated log files to a single output path. UI binding is in `packages/nightshade_app/lib/screens/settings/widgets/log_viewer.dart`. Users can attach this to bug reports. **No diagnostic dump screen exists** (e.g., one that bundles logs + active profile + sequence state + system info). Recommendation: add `screens/diagnostics/`. **MED**.

---

## 5. Settings / config layering

### a) Sources

Inventoried:
- Drift `app_settings` table → `AppSettings` (immutable, Freezed).
- Profile-specific via `EquipmentProfilesDao`.
- Riverpod `web_server_provider.dart:18-81` for runtime web-server state.
- Env vars: `NIGHTSHADE_HEADLESS`, `NIGHTSHADE_AUTH_TOKEN`, `NIGHTSHADE_PORT`, `NIGHTSHADE_CORS_ORIGINS`, `NIGHTSHADE_DATA_DIR`, `NIGHTSHADE_REFRESH_RATE`, `NIGHTSHADE_UPDATE_SERVER`, `NIGHTSHADE_UPDATE_CHANNEL`.
- CLI args: `--auth-token`, `--port`, `--cors-origin`, `--require-auth`, `--allow-unauthenticated-lan`, `--view-token`, `--control-token`, `--bind` (implied via auth-config inference).
- No `dart-define` compile-time flags discovered in scanned paths.

`apps/desktop/lib/main_headless.dart:153-275` shows **consistent env-then-CLI layering for the headless surface**: env vars seeded first, CLI overrides applied per-arg, default fallbacks last. Order is documented in comments ("env-first: NIGHTSHADE_CORS_ORIGINS is the systemd/docker idiom"). The GUI mode (`main.dart`) does not honour the same env vars — only `NIGHTSHADE_HEADLESS` — which is a deliberate separation but worth documenting.

### b) In-memory settings that should persist

Spot-check of `StateProvider`-shaped state: no obvious settings-class regressions. Per-screen ephemeral toggles (e.g., chart range pickers) are appropriately session-scoped.

---

## 6. Fail-closed audit completeness

### a) Rule coverage

`docs/production-readiness/fail_closed_rules.yaml` has **10 rules**. Verified each glob still matches its target file. The most aggressive — `handlers_e_tostring` — would currently flag **7 occurrences across 5 files**:
- `apps/desktop/lib/headless_api/handlers/auxiliary_handlers.dart` (2)
- `apps/desktop/lib/headless_api/handlers/flat_wizard_handlers.dart` (1)
- `apps/desktop/lib/headless_api/handlers/backup_handlers.dart` (2)
- `apps/desktop/lib/headless_api/handlers/mosaic_handlers.dart` (1)
- `apps/desktop/lib/headless_api/handlers/science_handlers.dart` (1)

And `handlers_status_failed_string` would flag at least:
- `apps/desktop/lib/headless_api/handlers/backup_handlers.dart:125, 159, 267, 349` (4)
- `apps/desktop/lib/headless_api/handlers/device_handlers.dart` (2)

These are real violations the gate would catch — **the gate is operational and finding gaps**. **HIGH** priority for triage in W3-AUDIT-TRIAGE.

### b) W5/W6/W7 paths missing rules

Scheduler (`packages/nightshade_core/lib/src/services/scheduler_service.dart`) and NINA import paths have no fail-closed rules but contain failure surfaces (target rejection, file-parse fallbacks). Defect-map build path is rule-less. **MED** — add three new rules in the YAML for these surfaces.

### c) Sequencer fail-closed verification

`native/nightshade_native/sequencer/src/executor.rs:969-983` correctly switches on `SafetyFailMode::{FailOpen, FailClosed, WarnOnly}`. Default is `SafetyFailMode::default()` at `:199`. **5 safety-critical paths spot-checked:** safety-monitor abort, weather-unsafe, meridian-flip abort (`:1291`), guide-star-lost trigger, mount-tracking-lost. All converge on `FailClosed` → emit event → halt sequence. Behaviour is correct.

Streaming checkpoint task runs every 30s (`executor.rs:1268`) and persists trigger state (`:1305-1313`). Crash recovery is well-served.

---

## 7. Threat-model coverage

### a) Bind address

`apps/desktop/lib/headless_api_server.dart:868-869`: binds to `loopbackIPv4` when `bindLocalOnly=true` (default in `HeadlessApiServer` constructor at `:154`). `main_headless.dart:271` flips `bindLocalOnly = false` when **any** token is configured. `apps/desktop/lib/main.dart:140, 160, 178` explicitly passes `bindLocalOnly: false` for the GUI's embedded server — relies on token auth being mandatory there. The interaction is documented at `headless_api_server.dart:878-881` with a runtime warning when unauthenticated LAN is in effect. **OK.**

### b) Token storage

Tokens live in process memory and CLI/env input — **no on-disk token files** discovered. Pairing-issued tokens persist via Drift `PairingDatabase`; SQLite at rest is unencrypted but file is in OS app-data dir (user-only ACL on Windows/macOS by default). **LOW** — acceptable for trusted-LAN model.

### c) CORS

`apps/desktop/lib/headless_api/auth/cors_policy.dart:13-50` implements explicit allow-list, **no wildcards**, with rationale documented in-source ("malicious local-loopback app on http://127.0.0.1:NNNN…"). High-risk paths drop the CORS header entirely on disallowed origins. **Strong.**

### d) WebSocket auth

`apps/desktop/lib/headless_api/auth/ws_ticket_manager.dart:14-50`: one-shot, 60-second tickets, constant-time compare, single-use consumption. Browsers cannot send `Authorization` on WS upgrade, so the operator first POSTs `/api/ws/ticket` with their bearer and presents `?ticket=` to upgrade. Tokens never appear in URLs or access logs. **Compliant with audit's trusted-LAN model.**

---

## 8. Crash / hang recovery

### a) Sequencer checkpoint

`native/nightshade_native/sequencer/src/checkpoint.rs:19` `CHECKPOINT_VERSION = 2`. `TriggerStateSnapshot` (`:23-60+`) covers HFR baseline, pier side, guiding, dither cadence, plate-solve hints — **comprehensive**. Background save loop in `executor.rs:1268-1320` writes every 30s. UI resume entry point exists in `widgets/session_recovery_checker.dart`. **OK.**

### b) Database corruption

Drift opens SQLite via `NativeDatabase.createInBackground` (typical). No explicit `PRAGMA integrity_check` or salvage path discovered. If `app_settings.db` corrupts, the app currently throws on `MigrationStrategy.onCreate` and never reaches UI. **MED** — recommend a corruption-detection helper that backs up the broken file, recreates the DB, and surfaces a one-time dialog.

### c) Background-service supervision

Discovery service (`webrtc/discovery`) does not appear to be supervised by a watchdog — if its `Future` errors out, the stream silently completes. **MED**.

### d) FFI panic handling

`native/nightshade_native/bridge/src/lib.rs:197` installs a `panic::set_hook`. `:457`, `:489`, `:557` wrap entry points in `catch_unwind` / `AssertUnwindSafe`. No `panic = "abort"` in any Cargo.toml — unwind is enabled, so `catch_unwind` works. **Good.** A Rust panic propagates as `NightshadeError::Internal("Task panicked")` via the `JoinError` From-impl (`error.rs:674-684`).

---

## 9. Operational / runbook gaps

**No `docs/RUNBOOK.md` exists.** For v2.5.0 GA the following are recommended:

1. **"App frozen on startup":** location of log dir per OS, how to retrieve via `LoggingService.exportLogs()`, env-var bypass (`NIGHTSHADE_HEADLESS=1` to start without GUI).
2. **"Plate-solve fails":** ASTAP install path, `--diagnostic plate-solve <fits>` CLI helper (currently absent — add).
3. **"OTA rollback":** the updater binary in `native/nightshade_native/updater/` should expose `--rollback`; verify against `packages/nightshade_updater/` provider state.
4. **"Sequence won't resume":** path to checkpoint files, schema version compatibility, manual recovery.
5. **"Headless server unreachable":** bind-address troubleshooting matrix (loopback vs LAN), token verification, CORS.

**HIGH** — runbook authoring is a hard prerequisite for a public 2.5.0 release.

---

## 10. Quick-win punch list

| Item | Type | Effort | Impact | Reasoning |
|---|---|---|---|---|
| Fix `NightshadeException._parseJson` dead-code (line 98-106 of `nightshade_exception.dart`); wire in `dart:convert.jsonDecode` | consolidate-error-type | **S** | **HIGH** | Restores the entire structured-FFI-error pipeline that Rust already serializes. One-line `try { return jsonDecode(message) as Map<String, dynamic>?; } catch (_) { return null; }`. Currently every typed Rust error is degraded to string heuristics. |
| Triage 13 `handlers_e_tostring` + `handlers_status_failed_string` violations in headless handlers | tighten-fail-closed | **S** | **HIGH** | Gate already detects them; structured error helper exists. Mechanical replacement. Eliminates network leakage of stack traces and HTTP-200-on-failure footguns. |
| Add `docs/RUNBOOK.md` covering 5 incident scenarios | add-runbook | **M** | **HIGH** | No code change; unblocks GA. First responder time-to-diagnosis drops from "read source" to "follow checklist." |
| Replace 477 raw `print/debugPrint` calls with `LoggingService.log` (start with top-10 file list in §2b) | improve-logging | **M** | **MED** | Brings file rotation, level filtering, and export coverage to runtime-hot paths. Allows `RUST_LOG`-style runtime tuning via the existing service. |
| Redact bearer token in `main_headless.dart:236` and add SQLite corruption-recovery wrapper | persist-setting / improve-logging | **S** | **MED** | Two small fixes that close a token-in-logfile leak and prevent first-launch-broken installs from being unrecoverable without filesystem surgery. |

**Top 3 by impact/effort:**

1. **`_parseJson` dead-code fix** (S/HIGH) — single-method change resurrects the entire structured-error path.
2. **Handler `e.toString()` + `'status':'failed'` cleanup** (S/HIGH) — pre-existing fail-closed rules already flag 13 sites; turning the gate red and fixing them is mechanical.
3. **Runbook authoring** (M/HIGH) — pure documentation; required to ship 2.5.0 to non-developer users.

---

*Generated 2026-05-12. Read-only audit. Only file written: `docs/code-quality/audit-observe.md`.*
