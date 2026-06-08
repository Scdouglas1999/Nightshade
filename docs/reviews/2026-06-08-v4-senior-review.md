# Senior Code Review — Smart Morning Report + 4.0 "Couch Control"

- **Date:** 2026-06-08
- **Range:** `cd8724d3..HEAD` on `feature/v4-couch-release` (24 commits, 299 files)
- **Method:** 10 adversarial area reviewers → independent refutation of each serious finding (default-to-refuted) → tech-lead synthesis. 38 findings, 9 serious, **8 verified after refutation**.
- **Verdict:** **NOT approvable as-is — `approve_after_blockers`.** Strong craft, but eight release-gating defects across hardware-safety, authorization, concurrency, and silent data-loss/dead-feature. Fixable, but must be fixed *and validated on real hardware/devices* before a human signs off.

> The most polished-looking features (the morning report, the push safety alerts, the unattended recovery) are precisely the ones that are silently broken. They will demo fine and fail in production with no error.

---

## Blockers (must fix before human approval)

### 1. Unattended reject-storm `PauseForOperator` abandons the rig — dome open, ALL safety triggers disabled
`executor/mod.rs:3571-3608` (Paused branch) vs `:3675-3748` (give-up safe-state sweep); trigger gate `:3850-3853`. *(Phase G regression.)*
The Paused branch freezes the tree but never runs `park_and_close_safe_state`, and the trigger monitor does `if current_state != Running { continue; }` — so weather/altitude/dawn triggers stop evaluating. On an unattended night a reject storm (rolling clouds/dew) leaves the rig dome+cover open with safety monitoring OFF until dawn. **Can lose the optics, not just the night.**
**Fix:** run `park_and_close_safe_state` on this branch (mirror the give-up branch), or keep safety-class triggers evaluating while Paused-due-to-recovery; at minimum gate the escalation behind an explicit attended/operator-present setting.

### 2. Resume from `PauseForOperator` leaves tracking OFF → trailed frames
`executor/mod.rs:3571-3608` + Resume handler `:2473-2482`; contrast recovered branch `:3622-3658`. *(Phase G regression, sibling of #1.)*
Recovery entry stops tracking (the default); the recovered branch restores it (loud error on failure), but this branch never does, and generic Resume doesn't re-enable it. Resume → exposing on a non-tracking mount, every frame trails, UI says "Running," no warning.
**Fix:** don't stop tracking for this cause, or restore it (with loud-error-on-failure) on resume.

### 3. Cross-device IDOR — any paired client can register/delete/mute another device's push
`push_handlers.dart:62-107/115-145/150-177/185-239`. *(Phase D.)*
Every handler trusts `deviceId` from the request and validates only `getPairedDevice(deviceId)!=null` — never that the deviceId belongs to the authenticated caller. A low-trust/guest/stolen control token can delete another operator's critical-alert delivery, mute weatherUnsafe/guidingLost, or hijack delivery. **Direct safety-paging compromise.**
**Fix:** resolve the caller's deviceId from the authenticated session and require `body.deviceId == caller`; 403 on mismatch. Add explicit `/api/push/*` scope entries.

### 4. Drizzle silently drops calibration — uncalibrated master swapped in as canonical
`finishing_combine.rs:206-301` + `post_session_integration_service.dart:642-748`. *(Phase C.)*
`drizzle_integrate_impl` deposits raw sub pixels — no dark/flat/bias anywhere; masters are only applied in-memory inside `api_integrate_session` and never reach the drizzle. On success `_runDrizzle` re-stamps the drizzled (raw) FITS as THE persisted master → amp glow, hot pixels, vignetting, dust. **Silent archival corruption.**
**Fix:** plumb the calibration block into `DrizzleIntegrateArgs` and calibrate each frame before depositing, OR write per-sub calibrated frames to disk and feed those paths to `_runDrizzle`.

### 5. Smart Morning Report intelligence is structurally dead in production
`post_session_integration_service.dart:288-292` → `optimizer.rs:243-248`. *(Morning report / Phase C.)*
`_analyzeAndStoreCurve` emits only `{snr,fwhm?,ecc?}`; `noise` doesn't exist on `PerFrameRecord`, so serde defaults it to 0. `integration_curve` only accumulates when `noise>0`, so every `CurvePoint.snr` is 0, `target_snr` anchors to 0, and `pushDeficitToScheduler` early-returns forever. **The entire "how much more integration do I need?" loop — the core of the release — never fires.** The unit test masks it with a scripted fake seam.
**Fix:** surface per-sub `noise` (ideally background/starCount) through the integrate FFI (it's already measured in `FrameQuality`), or add a `noise<=0` fallback in the optimizer. Add a test that drives the REAL `analyzeNight`.

### 6. Multi-filter night silently drops all non-dominant-filter subs
`auto_integration_service.dart:76-112`. *(Morning report.)*
When a target has an accumulating master for its dominant filter, only dominant-filter subs are folded and the method returns; non-dominant filters' accepted subs are never integrated, and the toast reports only the dominant count. **LRGB/SHO throws away a whole night's S and O subs with no master and no warning.** Untested file.
**Fix:** iterate every filter bucket (fold or batch-integrate each); make the toast reflect total subs across filters.

### 7. Built-in guider start/stop race orphans a mount-pulsing loop
`builtin_guider.rs:376-414`. *(Phase F.)*
`start_guiding` releases the lock, spawns the loop, then re-acquires to store `stop_flag/task`. In that window a concurrent `stop()` finds `None`, signals nothing, returns Ok — and the orphaned loop keeps issuing `mount_pulse_guide`; start then overwrites the handle so stop is permanently lost. Entry points don't serialize. **The mount gets nudged during slew/park/flip while the UI believes guiding is stopped.**
**Fix:** store `stop_flag/task` under the same write-lock that sets `guiding=true`, before releasing/spawning; or guard start/stop with a dedicated async op-mutex.

### 8. APNs token no-op gate never reset on server switch
`push_registration_service.dart:213` + `mobile_connection_ops.dart:101`. *(Phase E.)*
`_postToken` suppresses the POST when `token==_lastRegisteredToken` before considering the updated target; `reset()` is never called. APNs returns the same token across servers, so after registering with server A, re-pairing server B skips the POST → server B never learns the token → no cellular alerts. **Silent loss of the safety-push path, survives restarts.**
**Fix:** call `reset()` on disconnect/unpair/server-switch, or key the no-op gate on `(target + deviceId + token)`.

---

## Should-fix (high value, not release-gating)
- `park_and_close_safe_state` dome close is fire-and-forget — a shutter jammed half-open after accepting the close reports "safe" (`device_ops.rs:1075-1078`). The per-instruction path was hardened; this safety-critical sweep wasn't.
- `wait_for_dome_shutter_state` returns Ok when the dome never reports a definite state (`instructions.rs:5094-5116`).
- FCM 400 unconditionally prunes the token, silently losing future alerts (`remote_push_delivery.dart:335-338`).
- Push handlers accept revoked/inactive deviceIds for registration/prefs.
- Hard-delete of a paired device orphans push token/prefs; stale mute-prefs re-attach on re-pair, suppressing alerts.
- `pushDeficitToScheduler` is not idempotent — re-running double-counts the deficit into `frame_count`.
- Accumulate filter match is untrimmed while dominant is trimmed — whitespace-padded filter names drop subs.
- RA/Dec Peak guide tiles wired to never-populated fields — always render 0.00.
- iOS `aps-environment=development` ships with docs wrongly claiming Xcode auto-rewrites to production.
- AppDelegate `willPresent` override is shadowed by flutter_local_notifications — its "force critical sound" never runs for remote alerts.
- Drizzle preview-PNG write failure aborts the whole expensive drizzle run.

---

## What genuinely looks solid
- **W1–W5 preservation:** ZERO diff to the Sun gate, completion-redispatch, park-at-dawn+hysteresis, the W5 OR-trigger/AND-gate. No regression to the preserve-exactly invariants.
- **Native imaging math:** drizzle box-overlap flux-conserving + tested against analytic area; RL update direction/flip verified; Theil-Sen+Tukey color fit beats OLS under contamination; optimizer weighted-mean SNR + never-harm floor correct; NaN/inf/div-zero guarded.
- **DB migrations:** v42/43/44 idempotent, `_columnExists`-guarded, correct onUpgrade order, FK targets exist, real migration tests, no SQL injection.
- **FFI/bridge contract:** disciplined JSON-in/out, DTOs camelCase-matched, errors → `Err(String)`, no panics on bad input, IntegrationProgress wired.
- **Push crypto core:** ES256 nonce from `Random.secure()`, correct base64url JWS, secrets path-referenced and gitignored. (Weakness is authorization, not crypto.)
- **Rust async concurrency:** no MutexGuard-across-await in the executor; async locks / scoped guards before awaits; meridian `simulate` false at every production site. (Guider race is the exception.)
- **Pristine-master default + mechanical refactors:** the default persists an unmodified linear master; ASCOM exposure-apply extraction behavior-preserving; WCS CD-matrix conversion round-trips.

---

## Top residual risks (cannot be fixed by review)
1. **No on-sky validation** — the unattended executor, recovery escalation, park/close, and meridian logic have never run against real hardware under real failure modes (clouds, dew, jammed shutter). The two safety blockers surface exactly on a real bad night.
2. **No real push round-trip** — FCM/APNs delivery, JWT, token lifecycle never hit live Apple/Google endpoints. The IDOR + dev-entitlement + no-op gate + FCM-400 pruning all converge on "operator silently stops getting safety alerts."
3. **iOS never compiled** — entitlements/AppDelegate correctness inferred from source only.
4. **Tests give false confidence on the dead feature** — morning-report tests use a scripted fake seam returning non-zero curves; green CI ≠ working intelligence.
5. **Pattern risk** — AI-generated, hardware-controlling code that misses safety/authorization *intent* (reuse operator-pause for an unattended failure; restamp uncalibrated as canonical; trust client deviceId). Review caught these; the same class may exist in unreviewed corners.

---

## Recommended sequence to a real approval
1. Fix safety blockers #1 + #2 together (shared recovery branch; highest consequence).
2. Fix the guider start/stop race (#7) — same hardware-motion class.
3. Fix the push IDOR (#3) + fold in revoked-device + FCM-400 should-fixes (same files).
4. Fix the two silent data bugs: drizzle calibration (#4) + multi-filter dropping (#6) + whitespace-trim sibling.
5. Fix the dead morning-report curve (#5): surface per-sub noise through the FFI (or add the fallback) **and** add a test that drives the real `analyzeNight`.
6. Fix the APNs no-op gate (#8) + aps-environment + AppDelegate critical-sound together.
7. Add regression tests for the multi-filter path and deficit idempotency (both untested).

**Then, before human approval:** (a) a hardware-in-the-loop unattended night that forces a reject-storm and confirms park+close+triggers; (b) a live FCM + APNs round-trip including a server-switch and unpair/re-pair; (c) an actual iOS device build confirming the critical-alert sound fires.
