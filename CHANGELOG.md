# Changelog

All notable changes to Nightshade are documented in this file.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Engineering cross-references in the form `(§N.M)` point at the
`docs/plans/2026-05-09-v250-audit-fixes.md` v2.5.0 pre-release audit and are
intended for code reviewers rather than end users.

## [2.5.0] - 2026-05-11

This is the v2.5.0 hardening release. The headline change is the merge of two
previously parallel HTTP servers into a single, secure, fully-featured headless
API: the GUI and headless desktop modes now expose the same endpoint surface,
the same authentication flow, and the same web dashboard. A 7-agent pre-release
audit (see `docs/plans/2026-05-09-v250-audit-fixes.md`) drove a wide sweep of
silent-failure fixes across the sequencer, drivers, OTA updater, FITS pipeline,
and headless API. Highlights:

- The internal "fake" plate solver that returned commanded RA/Dec verbatim has
  been removed from the public solve path. Plate solving now requires ASTAP or
  astrometry.net, and the UI guides users through configuring one.
- The OTA updater no longer silently skips locked files, partial backups have
  been replaced with full move-then-copy backups, post-install hash
  verification has been added, and `cleanup_staging` no longer deletes its
  backup-bearing parent directory.
- The headless API now reports correct HTTP status codes on failure
  (no more `200 OK` with `{"status":"failed"}` bodies) and validates all
  request payloads through a shared helper that returns structured 400s
  instead of leaking stack traces in 500 responses.
- Mobile QR pairing now schema-validates payloads and shows a fingerprint
  confirmation sheet before connecting. The mobile auth token is now stored
  in Keychain / EncryptedSharedPreferences instead of plaintext
  `SharedPreferences`.
- The web dashboard now has a real pairing flow in headless mode, press-and-
  hold mount controls (the old single-click slewed indefinitely), an HttpOnly +
  CSRF "remember me" path, a phone layout, and a full accessibility pass.

### Added

#### Authentication, pairing and security
- HttpOnly + `SameSite=Strict` cookie auth path with per-session CSRF token
  for the dashboard "remember me" flow. Replaces the previous
  `localStorage`-backed bearer token storage (§2.5).
- Real pairing flow in headless mode: `POST /api/pairing/start` and
  `POST /api/pairing/verify` are now part of `HeadlessApiServer`, and
  `info.pairingSupported` is `true`. First-run web onboarding no longer
  requires reading the bearer token from the console (§2.1).
- Pairing-attempt LRU eviction map so the rate-limit data structure cannot
  grow unbounded under attack (§2.20).
- WebSocket auth via short-lived one-time tickets issued by
  `POST /api/ws/ticket`. Eliminates the previous `?token=…` query-string
  WebSocket auth that ended up in HTTP access logs (§2.28). The legacy
  `?token=` form is still accepted with a deprecation warning and will be
  removed in v2.6.
- Constant-time bearer-token comparison shared across the headless API and
  the LAN-push receiver via `apps/desktop/lib/headless_api/auth/timing.dart`
  (§2.22).
- Explicit CORS allow-list. `Access-Control-Allow-Origin` is no longer
  reflected from the request `Origin` header on high-risk POSTs (§2.27).
- Mobile QR-pairing payload schema validation, RFC1918 / link-local /
  `.local` host check, and a fingerprint-confirmation sheet before
  persisting any pairing (§3.1).
- Mobile auth-token migration to `flutter_secure_storage` (Keychain on iOS,
  EncryptedSharedPreferences on Android). First launch migrates the token
  out of plaintext SharedPreferences (§3.3).

#### Dashboard and headless API
- Web-dashboard phone layout (`.layout--phone`) with bottom-tab navigation
  (Devices / Mount / Camera / Sequencer / Log) at ≤ 600 px, and ≥ 48 px tap
  targets across all dashboard controls (§2.13, §2.7).
- Accessibility pass on the dashboard: `aria-label` on every icon button,
  `aria-live="polite"` toast region, keyboard d-pad navigation (§2.15).
- Per-device-type panel-enable state based on `state.connectedDevices`
  with `aria-disabled` + tooltip when the relevant device is absent (§2.12).
- Initial-connect retry with exponential backoff (250 ms / 1 s / 4 s)
  with progress surfaced to the user (§2.16).
- Headless API request-validation helper (`requireString`, `requireInt`,
  `requireDouble`, `optionalString`, ...) with a `BadRequestError` →
  HTTP 400 middleware. Used across every handler under
  `apps/desktop/lib/headless_api/handlers/` (§2.21).
- `/api/files/browse` path allow-list (Documents, configured save path,
  configured backup dir, configured calibration-library dir). Paths that
  do not canonicalize under one of those roots are rejected (§2.24).
- Stable backup IDs: backups now carry a UUID stamped into the filename
  (`nightshade-backup-{timestamp}-{uuid}.zip`) so REST delete/download
  cannot collide across processes (§2.25).
- Per-device-type discovery error aggregation in `/api/discovery`:
  failures are no longer swallowed by a bare `catch (_)`; the response
  now contains a `discoveryErrors` map alongside the discovered devices
  (§2.26).

#### Sequencer
- `RecoveryAction::Dither(DitherConfig)` and `RecoveryAction::Recenter`
  variants. Standard "Dither Interval" and "Drift Limit" triggers now use
  them (§1.5, §1.11).
- `TriggerType::DriftLimit { max_pixels: f64 }` plate-solve drift trigger.
  Wired into the trigger monitor; default action is `Recenter` (§1.11).
- `RecoveryAction::Retry { max_attempts }` is now a real implementation
  for triggers (was a silent no-op). The default "Guiding Failure" trigger
  now actually retries (§1.5).
- `TriggerState::on_pier_side_observed` and `clear_flipped_state` to
  correctly reset `has_flipped_this_target` when an observable pier-side
  change indicates a second meridian crossing (§1.9).
- Shared `Arc<RwLock<RuntimeConfig>>` for dither config, location, and
  filter offsets. `UpdateDitherConfig`, `UpdateLocation`, and
  `UpdateFilterOffsets` runtime commands now take effect immediately
  (previously they only `tracing::info!`'d) (§1.8).
- `terminate_with(triggers, reason)` helper in `executor.rs` so every
  trigger-monitor exit path sets `is_cancelled = true` consistently (§1.18).

#### Drivers and bridge
- `VendorSdk` trait and `load_vendor_sdk!` macro consolidating the ~80%
  duplicated FFI-loading boilerplate across vendor wrappers (ZWO migrated
  first as proof-of-pattern; 12 vendor migrations queued for v2.5.1) (§5.20).
- `bridge/src/dispatch/{ascom,alpaca,indi,native}.rs` split of the
  previously 9355-line `bridge/src/devices.rs`. The top-level dispatch
  file is now a thin router (§5.21).
- Alpaca `ImageBytes` binary protocol support with JSON fallback. The
  binary path sends `Accept: application/imagebytes` and parses the v3
  binary header; ~10× throughput improvement over JSON for large frames
  (§5.13).
- `MountStatus::availability` map exposing `FieldAvailability` per status
  field (`Available` / `Unsupported` / `Error(reason)`) so the UI can
  distinguish "mount reports X" from "unsupported by driver" from
  "transient read error" (§5.4).
- Per-EAF-model focuser step size in the vendor quirks database keyed by
  USB VID/PID. Replaces the previous hardcoded `8.0 µm` that was wrong
  on EAF-S / EAF-2 hardware (§5.8).

#### Desktop UI
- `NightshadeDialog` scaffold in `nightshade_ui` (header, body, close
  button, consistent corner radius and border). Replaces hand-rolled
  one-off dialogs across equipment / sequencer / imaging screens (§4.6,
  §4.20, §4.32).
- `BreakpointTokens` in `nightshade_ui` replacing every raw `< 1100`,
  `< 1024`, etc. comparison with named tokens (§4.32).
- `CollapsibleSidebar` in `nightshade_ui`, consolidating the duplicate
  animation logic that equipment and sequencer each carried (§4.32).
- `EmptyState` widget in `nightshade_ui` adopted by the analytics tab,
  diagnostics tab, and other screens that previously stacked many
  "no data" cards (§4.12, §4.24).
- Shimmer / `SkeletonBox` loading states for every Riverpod
  `loading: () =>` arm in the screens directory (§4.29).
- Visibility-aware periodic timers across screen-level dashboards
  (framing, discovery) — timers suspend when the route is hidden (§4.33).
- Keyboard focus rings on custom interactive widgets (draggable nodes,
  profile sidebar rows, dashboard tiles) (§4.31).
- Tooltips on every icon-only `IconButton` across the desktop UI (§4.30).

#### Mobile
- iOS background-limit honest banner: when a sequence starts on iOS the
  app shows "iOS may pause monitoring while this app is in the
  background. Keep the app foreground or rely on push from desktop." A
  real `UIBackgroundModes` solution is tracked as a v2.6 item (§3.2).
- WebSocket-driven mobile liveness with a 30 s grace window before
  declaring a disconnect. Replaces the previous 5-second / 3-strike poll
  that dropped in-flight session control on transient network blips
  (§3.6).
- Mobile token field is now `obscureText: true` with a visibility toggle
  (§3.4).
- Notification deep-links: tapping a `sequence_complete` /
  `sequence_failed` / `image_ready` push notification now navigates to
  the relevant screen via `go_router` deep-link (§3.8).
- Android immersive mode is now a user setting (default: `leanBack`)
  instead of forced `immersiveSticky` (§3.13).

#### Plate solving and imaging
- WCS keyword parse errors now propagate. CRVAL1/CRVAL2/CD1_1/CD1_2/CD2_1/
  CD2_2 are no longer `unwrap_or(0.0)`'d; malformed values surface as
  `PlateSolveError::WcsParse` (§6.4).
- XBAYROFF / YBAYROFF support for correct subframe Bayer pattern
  composition when crop offsets are odd (§6.6).

#### OTA updater
- Hash verification of every file in the staging manifest after apply.
  The boot-time `verifyPendingInstall` step now re-hashes the executable
  against the recorded post-install hash and refuses to mark the update
  verified on mismatch (§7A.3).
- File-lock at `<install_dir>/updates/.updater.lock` prevents concurrent
  updater runs (§7A.6).
- LAN-push package size cap (1 GiB, configurable) enforced before
  manifest signature verification can write any byte (§7A.7).
- LAN-push receiver refuses to start if no
  `NIGHTSHADE_UPDATE_PUBLIC_KEY` was compiled in, and logs an actionable
  message telling the user to rebuild with the dart-define (§7A.7).
- ZIP archives are now stream-extracted via `archive`'s `InputFileStream`
  instead of being loaded whole into memory (§7A.8).
- `staged_verified.marker` written after manifest + package SHA-256
  verification. `_bootstrapUpdater` refuses to copy `updater.exe` unless
  the marker matches the current manifest (§7A.9).

#### Production audit tooling
- `behavioral_audit.dart` and `placeholder_audit.dart` now scan via path
  globs over runtime locations instead of the previous hardcoded
  17-file allowlist. New patterns: `catch (_)`, `?? null|0|false|''|""`,
  `let _ =`, `.unwrap_or_default()`, `.ok();`, comment patterns
  (`// best effort`, `// silently ignore`, `// for now`, etc.) (§7B.1, §7B.2).
- `fail_closed_check.dart` is now driven by
  `docs/production-readiness/fail_closed_rules.yaml` and applies its
  rules to all matching files instead of a hardcoded list (§7B.3).
- CI baseline assertions (`--min-files` flag) so accidental reductions
  in audit coverage are detected (§7B.4).

### Changed

- ASCOM camera `CameraStatus.exposure_remaining` is now computed from
  `PercentCompleted` instead of always being `None` — sequence ETA
  display is now accurate (§5.19).
- `MountStatus.at_home`, `sidereal_time`, `pier_side`, `tracking_rate`,
  `alt`, `az` are now `Option<T>` and accompanied by an
  `availability` map. Previously fabricated `false` / `0.0` /
  `Sidereal` / `Unknown` on read failure (§5.4).
- `MountStatus.sideOfPier` is now nullable across Dart bridge bindings
  (FRB-regenerated). UI consumers display "—" for `null` / "unsupported"
  / an error icon as appropriate.
- ZWO / QHY / Player One cameras now track real cooler state via
  `Mutex<CoolerState>` in the device struct. Status reads return the
  actual cooler-on value instead of hardcoded `false` (§5.7).
- INDI mount methods (`is_parked`, `is_tracking`, `is_slewing`) now
  return `Result<bool, IndiError>`. A disconnected INDI client no longer
  reads as "not parked, not tracking" (§5.15).
- Alpaca `download_image_data_typed` reuses the pooled HTTP client.
  Per-request timeouts are now applied via `RequestBuilder::timeout(...)`
  instead of constructing a fresh `reqwest::Client` per image (§5.12).
- FWHM / HFR formulas are now internally consistent. `calculate_hfr_at_point`
  computes the true encircled-energy 50% half-flux radius (matching
  NINA / SGP / PixInsight convention) and FWHM uses `2.0 × HFR`. The
  previously-reported FWHM was ~25% over-stated (§6.11).
- Auto-stretch (STF) is now MAD-based (median ± `2.8 × 1.4826 × MAD`)
  matching the PixInsight reference instead of the previous hardcoded
  0.001 / 0.999 percentile clip. Faint nebula and LRGB integrations no
  longer peg to bright stars (§6.9).
- Web-dashboard mount d-pad is now press-and-hold (`pointerdown` /
  `pointerup` / `pointerleave` / `pointercancel`) instead of `click`-and-
  slew-forever (§2.7).
- Web-dashboard image fetch is now driven only by `exposure_complete` /
  `image_ready` events. The hardcoded `setTimeout(exposureTime + 2s)`
  fallback has been removed (image fetch will retry once if the event
  is missed within `exposureTime + 30s`) (§2.8).
- Web-dashboard pier-side display now uses a centralized
  `formatPierSide(value)` helper: `1 → "East"`, `0 → "West"`,
  `-1 → "Unknown"`. Previously rendered the raw integer (§2.9).
- Web-dashboard 3 s polling has been replaced with WebSocket-driven
  panel state. Polling remains only as a fallback when the WebSocket has
  been disconnected for > 10 s (§2.10).
- Dashboard CSP `connect-src` restricted to `'self' ws: wss:`. The
  previous `http://*:* https://*:*` allow-anything policy is gone (§2.4).
- Web-dashboard guide-graph WebSocket payload field names unified
  (`raPx` / `decPx`) and documented in `docs/api/web-server-api.md` (§2.14).
- Sequencer trigger-state writes are now `state.write().await` instead
  of `try_write()`. Updates to target name, target RA/Dec, HFR baseline,
  exposure count, plate-solve drift baseline, autofocus invalidation,
  and completed-integration counter no longer drop silently under
  contention (§1.1).
- Sequencer HFR "median" is now a real sorted-array median (NaN- and
  zero-filtered) instead of the previous exponentially-weighted moving
  average that was labelled "median" (§1.2).
- `SessionCheckpoint` now persists the full `TriggerStateSnapshot`
  (`last_autofocus_frame`, `last_dither_frame`, `baseline_hfr`,
  `has_flipped_this_target`, `tracking_limit_detected_at`,
  `current_filter`, `grid_dither_index`, `triggers_enabled`,
  `safety_fail_mode`, `filter_focus_offsets`). Resume no longer can cause
  a double meridian flip on the same target. `CHECKPOINT_VERSION` bumped
  with backward-compat default-on-missing migration (§1.3).
- Single `CheckpointManager` is now shared via `Arc` between the executor
  and the streaming-checkpoint task. UI staleness on
  `has_recoverable_checkpoint` is fixed (§1.16).
- `MeridianFlipExecutor` is now the canonical meridian-flip engine.
  `instructions::execute_meridian_flip` is a thin wrapper. Pier-side
  fallback to RA/Dec comparison, tracking-restore on cancel, autofocus
  parameters from the user equipment profile, and plate-solve-failure
  warning behaviour have all been backported into the executor (§1.6).
- `AutofocusConfig` user-facing struct now carries
  `backlash_compensation`, `outlier_rejection_sigma`,
  `use_temperature_prediction`, and `max_star_count_change`. Backlash
  no longer silently uses a hardcoded 50 steps regardless of user input
  (§1.7).
- `MeridianFlipExecutor::wait_settle` honours executor cancellation.
  Stop-during-settle returns immediately instead of waiting for settle
  completion (§1.17).
- Streaming-checkpoint cadence is now a dedicated 30 s
  `tokio::time::interval` task owned by the executor. Checkpoints no
  longer stop being written when `triggers_enabled = false` (§1.14).
- `apps/desktop/lib/headless_api_server.dart` is now the GUI-mode HTTP
  server too. `packages/nightshade_webrtc/lib/src/web_server.dart` has
  been deleted and `apps/desktop/lib/main.dart` routes both modes through
  `HeadlessApiServer` (§2.2).
- `secure_discovery.dart` now uses a structured JSON wire format
  everywhere. The previous `message.split(':')[1]` parse-by-position
  approach broke on device IDs that legitimately contain `:`
  (`native:vendor:idx`, `native:touptek:brand:idx`) (§3.11).
- Updater apply step is now move-then-copy: each destination file is
  renamed to `*.old` before the new file is written. On any failure all
  `*.old` files are renamed back; on success they are deleted. Previously
  the partial backup could not restore files added or modified outside
  the hardcoded backup set (§7A.2).
- `Process.start` → `exit(0)` race on updater launch hardened: the app
  verifies `pid != 0`, sleeps briefly, flushes the logger, and on
  `Process.start` exception restores the staged-update status (§7A.5).
- `behavioral_audit` rule definitions now live in YAML
  (`docs/production-readiness/fail_closed_rules.yaml`) instead of
  being hardcoded in the Dart program (§7B.1, §7B.3).
- INDI client jitter seeding is now per-instance via
  `fastrand::Rng::with_seed` instead of time-seed (§5.23).

### Fixed

#### Critical (data integrity, hardware risk, deceptive behaviour)
- Internal plate solver no longer returns the commanded RA/Dec / FITS-
  header coordinates verbatim and labels the result `success: true`.
  `solve_internal` has been removed from the public solve path. ASTAP
  and astrometry.net are now the only paths, and `is_solver_available()`
  reflects reality by checking for those binaries (§6.1, §6.2).
- FITS BSCALE/BZERO round-trip. Reading no longer leaves stale source
  BSCALE/BZERO entries in `header.keywords` after applying them to the
  data buffer. Writing emits only the freshly-computed BSCALE/BZERO for
  the chosen output BITPIX. COMMENT and HISTORY cards are emitted as
  proper standard cards instead of malformed `COMMENT_<n> = ...` value
  cards. String values are padded to ≥8 chars per FITS 4.2.1.1.
  `NAXIS > 3` is now rejected explicitly with
  `FitsError::Unsupported4DCube` instead of silently dropping planes
  (§6.3, §6.5).
- OTA updater no longer silently skips locked files with a same-size
  optimization. Locked files now retry up to 3 times, then either
  schedule a delayed-until-reboot replace or fail the update non-zero
  with an actionable message ("Update could not replace foo.dll because
  it is in use. Please close Nightshade and try again."). The previous
  same-size optimization could silently corrupt installs with
  different-content-same-size files (§7A.1).
- OTA updater backup now covers every file the apply step touches via
  move-then-copy `*.old` rename strategy. Previously the hardcoded
  3-file backup could not restore files added or modified outside that
  set (§7A.2).
- `cleanup_staging` now deletes `staging_dir` itself, not its parent.
  The previous behaviour wiped `backup/`, `pending_install.json`, and any
  future-staged update in one shot (§7A.4).
- `device_id.rs` `valid_vendors` allow-list is now generated from a
  single registry (`SUPPORTED_NATIVE_VENDORS` in `native/src/lib.rs`).
  Saved profiles for `playerone`, `meade`, `onstep`, `losmandy`,
  `10micron`, `fujifilm`, `gphoto2`, `qhy_cfw`, `fli_focuser`, `fli_fw`,
  `zwo:eaf`, `zwo:efw`, and 4-part Touptek IDs no longer get rejected
  on app start (§5.1, §5.2).
- Alpaca image-array download no longer silently substitutes `0` for
  pixel JSON values that fail to parse. Errors now surface as
  `AlpacaError::ParseError { offset, found }`. `Rank` is read from the
  JSON header and dispatched correctly so color-sensor frames (rank 3)
  no longer have a channel dimension silently dropped (§5.3).
- Sequencer HFR "median" now sorts and picks the true median.
  Previously the `((a+b)/2 + c)/2 + d)/2` shape was an exponentially-
  weighted moving average labelled "median"; HFR-degraded triggers
  fired on single bad frames (§1.2).
- Session-checkpoint resume no longer loses trigger state. A target
  that already flipped no longer flips a second time after resume.
  Autofocus and dither intervals no longer misfire after resume (§1.3).

#### Drivers
- `mount_get_status` no longer fabricates `at_home: false`,
  `sidereal_time: 0.0`, `alt/az: (0, 0)`, `tracking_rate: Sidereal`, or
  `pier_side: Unknown` on read failure. Each field is now `Option<T>`
  with an availability marker; the UI distinguishes "off" from "broken"
  from "unsupported by driver" (§5.4).
- SkyWatcher mount no longer returns `Ok(())` on
  `set_tracking_rate(Sidereal)` or hardcoded values for
  `get_tracking_rate` / `get_side_of_pier` / `get_alt_az` /
  `get_sidereal_time`. The minimum-viable fix returns
  `Err(NativeError::NotSupported)` so the sequencer refuses to schedule a
  meridian flip on this driver. Encoder-based decode of pier-side and
  alt/az is queued for a follow-up (§5.5).
- ZWO / QHY / Player One cameras `cooler_on` status now reflects reality
  instead of always-`false`. Dashboard no longer lies after
  `set_cooler(true)` (§5.7).
- ASCOM wrapper `cam.camera_x_size().unwrap_or(1)` and heuristic
  bit-depth substitution have been replaced with error propagation.
  Transient COM errors no longer produce 1×1 images with wrong bit
  depth; the bridge marks the camera disconnected instead (§5.9).
- ASCOM filter wheel `Names` property errors no longer get silently
  swallowed by `unwrap_or_default()`. The device is now marked unusable
  until reconnect; the UI does not show a 0-filter wheel (§5.11).
- LX200 `is_parked` returns `Err(NativeError::NotSupported)` for non-
  OnStep / non-Meade variants instead of always-`false`. Sequencer no
  longer believes a parked Losmandy / 10Micron mount is alive (§5.6).
- INDI client XML parser now uses a depth/parent stack
  (`Vec<(device, property, element)>`) instead of three flat current-*
  strings. Malformed streams with unbalanced `def*` no longer attribute
  element values to the wrong property. `Event::Empty` (self-closing) is
  now handled (§5.18).
- INDI camera `get_binning` / `get_frame` / `get_max_bin_x` now return
  `Result<Option<T>, IndiError>` distinguishing "not yet defined" from
  a real value. Callers wait briefly for property definition with a
  logged warning on fallback (§5.10).
- ASCOM `Drop` no longer races the COM apartment thread. The bridge
  wrapper preserves STA ownership on drop; `AscomCamera::Drop` defuses
  the connected flag and lets the STA worker perform the actual
  `disconnect` (§5.22).

#### Sequencer
- `RecoveryAction::Retry` and `Continue` and `CustomBranch` are no
  longer silently dropped by the trigger handler's `_ => {}` fallthrough.
  The default "Guiding Failure" trigger now actually retries (§1.5).
- `FlipFailureAction::AbortAndPark` no longer drops the park error with
  `let _ = mount_park(...)`. Park failures are now logged at `error!`,
  retried up to N times, emit a `CriticalSafetyEvent`, and propagate the
  error if retries exhaust (§1.10).
- `has_flipped_this_target` now also resets on an observable pier-side
  change back to the pre-flip side. Long single-target sessions that
  cross two meridians no longer silently skip the second flip (§1.9).
- `Arc::try_unwrap` failure on tree children no longer silently "leaves
  it out". Tree-corruption invariants now return `Failed` with a clear
  event (§1.12).
- Filename derivation no longer silently substitutes `"image"` for a
  missing target name or `"L"` for a missing filter. Missing
  fields return a configuration error; safe defaults are logged at
  `warn!` (§1.15).
- Dither RA-only fallback magic threshold (`dec_offset.abs() < 0.01`) no
  longer hijacks grid mode. Grid mode now always picks the nearest grid
  cell (§1.13).
- Retry-delay magic 60.0 in
  `meridian_flip_executor.rs:185-187` replaced with a clear configuration
  error when the user-supplied `retry_delays_secs` array is too short
  (§1.20).

#### Headless API
- 130 unsafe `payload['x'] as String` / `(x as num).toDouble()` casts
  across `apps/desktop/lib/headless_api/handlers/` now go through a
  `validatePayload` helper. Missing or wrong-type fields return HTTP 400
  with `{"error":"missing_field","field":"deviceId","expected":"string"}`
  instead of HTTP 500 with `e.toString()` leaking stack traces and
  internal types (§2.21).
- HTTP 200 with `{"status":"failed"}` is gone across backup, flat-wizard,
  mosaic, sequence-management, dome, safety-monitor, focus-model,
  session, guiding, auxiliary, filesystem, weather, transient,
  analytics, suggestion, profile, scheduler, planetarium, framing,
  target, imaging, sequencer, equipment, and device handlers. Failures
  now return non-2xx codes with a structured error body (§2.23).
- `_resolveAllowedOrigin` no longer reflects same-host CORS origins on
  high-risk POSTs. CORS now uses an explicit allow-list (§2.27).
- Error response bodies no longer include `e.toString()`. Internal
  errors return `{"error":"internal_error","requestId":"<uuid>"}` and
  the full exception goes only to the structured log (§2.29).

#### Imaging
- WCS keyword parse errors no longer silently produce a solve at
  RA=0/Dec=0/scale=0. CRVAL1/CRVAL2/CD* failures now propagate (§6.4).
- VNG debayer threshold has been corrected from `min_g + (max_g - min_g) *
  3 / 2` (always greater than max → no edge preservation) to the
  intended `(min_g * 3) / 2`. Every OSC frame now keeps edge detail
  instead of silently degenerating to 8-direction averaging (§6.12).
- Plate-solve `detect_local_maxima` threshold floor now uses
  `N_sigma × background_sigma_estimate` from the existing background
  estimator instead of a fixed 250-ADU floor that was meaningless on
  10-bit cameras and pre-stretched images (§6.15).
- XISF `Creator` / `CreationTime` now use the real package version
  instead of hardcoded `"Nightshade 2.0"` (§6.22).
- XISF boolean parse now accepts `True` / `TRUE` per spec (§6.21).
- PHD2 `get_app_state` unknown states now map to `Phd2State::Unknown(String)`
  with a warning log instead of silently being treated as `Connected`.
  `GuidingPaused` and `StarFound` have explicit variants (§6.23).
- RAW `CString::new` failures for bad-pixels / dark-frame paths now
  return `RawError::InvalidPath { which, source }` instead of being
  silently ignored (§6.25).
- Stale RAW comment about "located by sRGB gamma defaults" removed; the
  code uses `nightshade_libraw_apply_config` correctly (§6.24).
- Pickering airmass at altitudes below 10° no longer silently uses an
  out-of-validity-range formula. Altitudes below 0° now return `Err`
  (object below horizon) and the wider altitude range uses Young's 1994
  formula (§6.14).

#### Desktop UI
- The "future update" placeholder dialog on every connected device
  card's settings IconButton has been removed. Camera / focuser /
  mount / filter wheel / rotator gears now route to real per-driver
  settings; device types without settings (covercalibrator, switch,
  dome) hide the gear icon entirely (§4.1).
- Centering dialog now has an "Abort" `NightshadeButton` (destructive
  style) that calls the centering service's stop method,
  `barrierDismissible: false`, and `NightshadeColors` styling. The
  previous dialog had a disabled X with no Cancel/Abort path and broke
  the Red Night theme (§4.2).
- Build-side side effects removed from `imaging_screen.dart:351`,
  `sequencer_screen.dart:96-99 / :658-665`, `framing_screen.dart:67-69`.
  First-run dialogs no longer duplicate under rapid window resize / hot
  reload (§4.3).
- Flat wizard capture wait now subscribes to the `cameraImageReady`
  event instead of `Future.delayed(exposureTime + 500ms)`. Slow USB /
  large-sensor captures no longer false-error with "image not ready"
  (§4.4).
- Sequencer auto-collapse no longer writes back to user prefs. A
  derived `effectiveCollapsed = userPref || isSpaceTight` value is used
  instead, and a thin draggable rail remains visible below the minimum-
  width threshold so drag-and-drop still works (§4.7).
- Sequencer toolbar overflow menu replaces the previous 5-threshold
  hide-each-button cascade. On 1024×768 New/Open no longer silently
  disappear (§4.8).
- Imaging-screen control sections (Display / Filter / Exposure /
  Capture) now use a wrapping `Wrap` grid instead of horizontal scroll.
  Critical controls no longer scroll off the right edge unnoticed (§4.9).
- Planetarium filter sidebar uses `NightshadeColors.surface` /
  `surfaceOverlay` instead of raw `Colors.grey[900]`. Red Night theme
  now inherits correctly. Collapsed sidebar shows small status dots for
  each filter category (§4.15).
- Polar-alignment screen pulse animation only runs when
  `state.isRunning`. Battery / GPU no longer ticks every frame on a
  static dashboard (§4.23).

#### Mobile
- Manual-connect path no longer synthesizes `DiscoveredServer` with
  hardcoded `version: '2.0.0'` and `signalingPort: 45678` before the
  `/api/info` round-trip succeeds. Persisted last-server is reordered to
  fetch first, persist on success (§3.7).
- Disconnect detection moved out of `Consumer.builder`'s
  `addPostFrameCallback`. Cycle-under-fast-rebuilds is gone (§3.10).
- `_onNotificationTapped` no longer only `debugPrint`s the payload.
  `image_ready`, `sequence_complete`, `sequence_failed` now navigate
  via `go_router` deep-links (§3.8).
- Foreground-service notification text now includes
  `($percent%)`; the previous `_percentComplete` field was masked by
  `// ignore_for_file: unused_field` (§3.9).
- WebRTC discovery `Timer.periodic(2s)` is now tracked and cancelled
  on `stop()` / `socket.close()`. The previous unbounded timer leaked
  one per `startBroadcasting` call (§3.11).
- WebRTC discovery uses distinct fixed server port + ephemeral client
  port. Loopback datagram unreliability on Windows is gone (§3.11).

#### Production audit tooling
- Behavioral and placeholder audits no longer have a 17-file
  false-confidence blind spot. The expanded glob coverage applies to
  every new headless handler, the LAN-push receiver, the updater Rust
  binary, the OTA updater Dart code, and `apps/desktop/lib/widgets/
  update_manager.dart` (§7B.1).
- Excluded directory tokens are now name-anchored (`test`, `tests`,
  `example`, `samples`) instead of substring-matched. Production
  modules whose paths happen to contain those tokens are no longer
  silently skipped (§7B.2).

### Security

- **HttpOnly cookie + CSRF token on dashboard "remember me".** Token
  is no longer reachable from `localStorage` and therefore cannot be
  stolen by an XSS vulnerability on the dashboard origin (§2.5).
- **Constant-time bearer-token comparison** across the headless API
  and the LAN-push receiver. Timing-side-channel extraction of tokens
  character-by-character on a slow link is mitigated. Token-bucket
  rate-limit on comparison failures prevents DoS via the comparison
  loop cost (§2.22).
- **CORS allow-list, no reflection.** `Access-Control-Allow-Origin` is
  now set only for origins in an explicit allow-list (typically just
  the bound `http://127.0.0.1:<port>` dashboard). A malicious local
  process on `127.0.0.1` can no longer script high-risk POSTs (§2.27).
- **WebSocket auth via short-lived ticket.** WS connects via
  `?ticket=<60s-lifetime, one-time>` instead of `?token=<bearer>`.
  Tokens no longer end up in HTTP access logs, browser history, or
  proxy logs (§2.28).
- **`/api/files/browse` path allow-list.** Admin-scoped enumeration of
  the entire readable filesystem is no longer possible; paths must
  canonicalize under an explicit allow-list (Documents, configured
  save / backup / calibration-library dirs) (§2.24).
- **Mobile QR pairing schema validation + fingerprint confirmation.**
  Arbitrary JSON-shaped payloads pointing at attacker-controlled hosts
  are rejected; a confirmation sheet shows host + short-hash
  fingerprint before any pairing is persisted (§3.1).
- **Mobile auth token in secure storage.** Tokens are now in Keychain
  (iOS) or EncryptedSharedPreferences (Android). A lost phone no
  longer leaks full mount/camera control via `/data/data/.../shared_prefs/
  *.xml` or an unencrypted plist (§3.3).
- **LAN-push manifest signature verified before any byte is written.**
  1 GiB pre-signature size cap. LAN-push receiver refuses to start at
  all if `NIGHTSHADE_UPDATE_PUBLIC_KEY` was not compiled in, with a
  clear error rather than a silent-disabled state (§7A.7).
- **Updater file lock** at `<install_dir>/updates/.updater.lock`
  prevents concurrent updater runs racing on `pending_install.json`
  (§7A.6).
- **Dashboard CSP `connect-src` restricted to `'self' ws: wss:`.**
  Previous `http://*:* https://*:* ws://*:* wss://*:*` is gone (§2.4).
- **Dashboard startup warning when bound on a non-loopback address.**
  Operators who run `--bind 0.0.0.0` now see an explicit STDOUT banner:
  "Nightshade API listening on ALL interfaces. Anyone on your network
  can attempt to authenticate. Press Ctrl+C now if this is wrong."
  (§2.6).
- **`infile_select` / `dst_path` canonicalization** across the
  headless API path-accepting endpoints, not only `/api/files/browse`
  (§2.24).

### Deprecated

- Legacy WebSocket auth via `?token=<bearer>` query parameter. Still
  accepted for backward compatibility with v2.4 mobile clients, but
  emits a deprecation warning to the structured log. Will be removed in
  v2.6. Migrate clients to `POST /api/ws/ticket` then
  `?ticket=<short-lived>` (§2.28).
- `nightshade_webrtc` package name. Functionality has been narrowed to
  the discovery / collaboration / auth / database layers; the
  WebRTC-specific signaling and peer-connection code has been removed
  in this release. The package name is preserved for v2.5.0 binary
  compatibility and will be renamed to `nightshade_remote_api` in v2.6
  (§2.3).

### Removed

- `packages/nightshade_webrtc/lib/src/web_server.dart` (4,746 LOC). The
  GUI-mode HTTP server has been consolidated into
  `apps/desktop/lib/headless_api_server.dart`. GUI and headless modes
  now expose the same endpoint surface and the same dashboard (§2.2).
- `packages/nightshade_webrtc/lib/src/peer_connection.dart`,
  `signaling.dart`, and `signaling/secure_signaling_server.dart`. The
  WebRTC peer-connection / signaling stack was exported but never
  imported outside the package; live image preview still uses the
  polled-image endpoint. WebRTC for the image-preview path is queued for
  a v2.6+ design discussion (§2.3).
- `flutter_webrtc` dependency from `apps/desktop` and `apps/mobile`.
  Build time and APK / DMG size reduced accordingly (§2.3).
- Internal plate solver `solve_internal` from the public solve path.
  ASTAP and astrometry.net are now the only solvers; a real geometric
  matcher (4-star quad hashing or Tycho-2/Gaia-DR3 subset) is on the
  v2.6 roadmap (§6.1).
- Hardcoded `currentVersion: '2.0.0'` fallback in
  `nightshade_updater`'s update provider. A missing version-provider
  now logs at `error!` and refuses to start update polling per the
  CLAUDE.md "errors are a feature" ground rule (§7A.10).
- Bridge `device_id.rs` hardcoded `valid_vendors` duplicate. The
  registry now lives in `native/nightshade_native/native/src/lib.rs`
  (§5.1).
- Dead `escapeHtml` helper in the web dashboard (rendering uses
  `textContent` / `appendChild` correctly) (§2.18).

---

[2.5.0]: https://github.com/scdouglas1999/nightshade/releases/tag/v2.5.0
