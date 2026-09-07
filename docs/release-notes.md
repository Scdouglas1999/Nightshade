# Nightshade 7.0.0 Release Notes

## Release

- Version: `7.0.0` (build 27)
- Build date: 2026-09-07
- Channel: `alpha` (see `version.yaml`)
- Previous release: `6.2.0` (build 26)
- Headline: **Darkroom** — non-destructive recipe processing and networked morning delivery

## Release Summary

7.0 processes your night for you and never takes anything away from you to do it.

When a sequence completes, the **dawn autopilot** calibrates, registers and integrates your
accepted frames into per-filter linear master lights, composes a **first-draft recipe**
(gradient removal, denoise, colour calibration where the data supports it, an auto-fitted
stretch, an edge crop), renders a draft JPEG, and delivers everything wherever you want to
work in the morning. The draft is not a baked file: it is a *recipe* — an ordered, editable
stack of operations stored as data. Open it in the new **Darkroom** and every step the
autopilot took is there to adjust, reorder, disable or discard. "Reset to linear" always
exists and never destroys anything.

Alongside Darkroom, this release closes the behavioural audit register to zero open findings
for the first time, retires simulation mode's dead toggle, makes the observer location
explicitly *unknown* until you set one, and fixes a stacking-normalisation defect that shipped
in 6.2.0 (see Migration And Compatibility — 6.2.0 masters are void).

## Supported Platforms

| Platform | Status | Build artifact | Verification |
| --- | --- | --- | --- |
| Linux x64 | supported | `nightshade-7.0.0-linux-x64.tar.gz` (built by `.github/workflows/release.yml`) | Release bundle built from this tree and exercised end to end by the committed live harness (see Verification Summary). This is the platform every claim below was proven on. |
| Windows x64 | supported, **validation owed** | `nightshade-7.0.0-windows-x64.zip` (built on a Windows runner by `.github/workflows/release.yml`) | Not exercised for this candidate. No Windows build, bundle audit, golden re-capture or runtime walk was performed. The Windows runner-lifecycle fixes in this release are compile-level changes reviewed against the Win32 message loop; they have not been run. |
| Android | supported, **validation owed** | `nightshade-7.0.0.apk` | Built by CI; not installed or exercised for this candidate. |
| macOS | unsupported | — | Not built or tested. |

## Supported Hardware And Drivers

Unchanged from 6.2.0 — see `docs/supported-hardware-by-platform.md`. Two vendor
connect-behaviour changes land in this release (Player One bin/ROI refusal, Atik
undetermined-colour refusal) and **have not been exercised on hardware**.

## New Or Changed Features

### The Darkroom editor

- Step cards driven by each operation's own parameter schema, keeping three truths separate:
  what the recipe says, what validation says, and what the render actually did — including
  *why* a step was skipped (no photometric catalog on a fresh install is an explanation on
  the card, not a silent no-op).
- Branching: duplicate any recipe as a variant at the shared prefix; compare branches
  side-by-side or blinking with a shared zoom/pan. Autopilot drafts and your own recipes are
  marked by author.
- Export at any stage: the linear master, the image after step N, or the final render. FITS
  always carries the full recipe as provenance (HISTORY cards plus a `.nsrecipe` sidecar).
  Raster formats of a still-linear stage are a visible screen-transfer choice, never a silent
  auto-stretch.
- Undo/redo over your edits; renders are cancelled, never queued, when you keep dragging.
- A recipe carrying an op this build cannot run renders around it, says so per step, and
  offers removal with undo, instead of becoming a dead end.

### Honest calibration, honest colour

- Every master states exactly which darks/flats/bias were applied, per slot, with match
  quality and staleness — in the result, the FITS HISTORY and a `CALWARN` card. A missing
  master is an explicit entry. Agreeing on nothing is not a match.
- Colour calibration is a Johnson B−V regression against the shipped catalogs, scoped and
  labelled as such. It is not SPCC and is never called that. It refuses mono input loudly, and
  the dawn draft pins the fitted channel scales so previews render colour-correct at any zoom.
- Unknown gain/offset on your frames is matched as *unknown* (scored, reported UNVERIFIED),
  never compared as a fabricated zero.

### Delivery

- Targets: any watched folder (NAS mounts included), SFTP (key auth via the system OpenSSH),
  or a **paired desktop that pulls** — the rig publishes a signed manifest and your home
  machine fetches it with resumable downloads.
- Copy, never move. Atomic writes, checksum verification, bounded retries that survive a rig
  reboot, and a journal whose every status line derives from a recorded fact. There is no
  "configured" state that has not proven itself.
- Delivered filenames carry a rig identity, so two Nightshades sharing one drop folder cannot
  collide.

### Also in 7.0

- The behavioural audit register is at **zero open findings** for the first time: every
  silent-behaviour site was either fixed (~65 real defects, including vendor drivers that
  fabricated capabilities and safing paths that failed silently) or documented with the
  specific mechanism that makes it safe.
- Simulation mode's dead toggle is gone. The observer location is explicitly *unknown* until
  you set one; the backend is told null rather than 0/0/0.
- `NIGHTSHADE_DATA_DIR` is now the root of everything Dart writes — one resolver, 52 call
  sites.
- Idle frame rate: every 1 Hz clock is aligned to the epoch-second boundary. The idle frame
  rate was the number of clock phases, not the clock rate. An urgent status dot pulses for
  twenty seconds and then holds, so a failed run no longer costs a third of a core forever.
- A finished sequencer node says so: `NodeCompleted` now answers every `NodeStarted`.
- Retired: a dead sky-view widget, a test-data seeder that could write a fake observer
  location, an unwired timeout module, and ~14k lines of comment noise.

## Security And Remote Access

- Darkroom delivery egress is scoped to control; credential files are written `0600`.
- `--allow-unauthenticated` no longer outranks a configured token.
- SFTP uses key auth via the system OpenSSH. **Password auth is deliberately absent** pending
  a dependency decision.
- Unauthenticated hits on the new endpoints return 401; this was exercised in the break-it
  waves against a running build.

## Migration And Compatibility

- **Database schema v59.** The upgrade is atomic and takes a backup first; a failed migration
  does not brick the library. The migration probe from a v4.3.0 fixture runs in CI.
- **6.2.0 accumulating-master sidecars are refused.** 6.2.0 shipped a stacking-normalisation
  defect (a background-pair OLS fit that erased stars — retention 0.08%). The fix follows
  PixInsight's default additive-with-scaling normalisation. v1 sidecars are refused at
  `MASTER_STATE_VERSION 2`, so **masters and sidecars produced by 6.2.0 are void and must be
  re-integrated from frames.** Your captured frames are untouched.
- No other user-facing data migration is required.

## Known Limitations

- **On-sky validation is owed.** Everything in this release was proven against simulators on
  Linux. The colour path has not run against a real plate-solved master with real APASS/HYG
  photometry.
- **Windows validation is owed**: build, bundle audit, golden re-capture, SFTP key-file ACLs,
  and the runner-lifecycle changes in this release.
- **The polar-alignment rotation fix is not on-sky validated.** Three-point alignment now
  builds its rotation target in the mount's own frame (a target built from the *solved*
  coordinates made the mount absorb the very misalignment being measured, producing a
  two-axis swing toward the pole instead of a 10° RA step) and refuses a step that would
  cross the meridian. This is covered by unit tests and was reproduced from a live rig log,
  but the corrected path has not been run against a mount.
- The curves operation renders read-only in this build's editor (no curve control yet).
- `denoise` on very large RGB masters has a high peak-memory profile; an f32 plane fallback is
  identified if it bites.
- A server's full disk reports as a retryable transport failure, because SFTP cannot
  distinguish ENOSPC.
- With no observing site configured, the default altitude trigger currently skips targets; the
  run outcome states it.
- Weather safety is fail-closed by default: with no weather device and an API that has never
  been fetched, an unattended rig will park. Set `fail_open` if that is not what you want.

## Fixed Issues

Seventy commits since `v6.2.0`. The largest groups:

- **Darkroom break-waves one through six** (30, 21, 33, 22, unrecorded and 14 findings, by
  their own commit subjects) and **fix-fleet waves seven through nineteen**: every defect
  five adversarial agents could reproduce against the running build across UX honesty, data
  corruption, process kills, delivery faults and UI traps. Among them: a
  release-only UI freeze the framework's own debug assert cannot catch in production; a
  session-finalisation gap on the headless path that predated this release; a missing SQLite
  busy-timeout that let any external reader kill the daemon at startup; and four SFTP wire
  truths that only a real OpenSSH server disproved.
- **Stacking normalisation** follows PixInsight's default; stars survive integration again.
- **Calibration frames count**: a 3-frame dark run no longer reports 0/0 frames and 100%
  downtime.
- **Meridian handling**: the trigger reads the target's sky, not the mount's pointing; a
  parked or non-tracking mount does not arm the flip; preflight warns when the flip would
  re-centre without a solver.
- **Weather map**: labels above the clouds, honest zoom, tiles that retry, one `saveLayer` per
  tile, and a basemap that is not a wall of "API KEY REQUIRED" watermarks.
- **Catalogs**: the three download tiers were a placebo — one dataset, stated once, with HYG's
  real depth.
- **Plate solving**: solver verification is bounded by a deadline and reaps a hung probe (an
  ASTAP GUI build opens a window instead of exiting on `--help`), and the CLI executable is
  preferred over the GUI one wherever both are installed. Verification is no longer a
  synchronous bridge call on the UI thread.
- **USB hot-plug**: a bus event now schedules follow-up probes at ~3 s, ~13 s and ~43 s. A
  single immediate probe cached "nothing here" while Windows was still installing the driver,
  and the device stayed invisible until the five-minute fallback.
- **Windows runner lifecycle**: the Flutter controller is torn down while the window and COM
  apartment are still alive, a font-change broadcast during teardown no longer dereferences a
  released controller, and a `GetMessage` failure is reported as a failure.

## Verification Summary

Everything below was run on Linux against **this tree**, on 2026-09-07.

| Check | Result |
| --- | --- |
| Dart/Flutter suites (`melos run test`, 10 packages) | **6,871 passed, 0 failed** |
| Rust suites (`cargo test --workspace`) | **2,819 passed, 0 failed, 23 ignored** |
| Rust clippy (`-D warnings` + `result_unit_err`, `await_holding_lock`, `undocumented_unsafe_blocks`) | clean |
| `cargo fmt --all --check` / `dart format` | clean |
| Production gate set (25 gates, mirroring `.github/workflows/ci.yml`) | **25 passed, 0 failed** |
| Behavioural audit | 0 open, 0 unregistered (3,109 files) |
| D1 live sim-night, release bundle | **38 assertions passed, 0 failed** |
| D1 crash-resume leg | **3 passed, 0 failed** |
| D1 two-nights leg | **23 passed, 0 failed** |

The three live legs ran against the release bundle built from this tree
(`apps/desktop/build/linux/x64/release/bundle`), with the native library rebuilt first and the
shipped `.so` string-checked for this release's own fixes — `flutter build` does not rebuild
Rust, and a stale `.so` mimics a working fix.

The sim-night leg covers: fresh install → simulator-bound profile → LRGB sequence to natural
completion → per-filter masters with non-zero integration and real star contrast (worst 109
ADU against a 30 ADU floor) → dawn Darkroom job queued→running→done → autopilot recipes with
draft JPEGs and `.nsrecipe` sidecars → delivery journal rows with checksums → files
byte-identical in the drop folder → operator grading thresholds reaching the executor and
rejected frames filed under `Reject/` → a crash-resumed pass re-queueing and delivering
without a destination conflict.

Golden pixel-diff tests are excluded by policy: the committed baselines are Windows-captured
and produce false diffs on a Linux host. See `docs/testing/golden-tests.md`.

**Not verified for this candidate:** any Windows build or runtime behaviour, any Android
runtime behaviour, any real hardware, and anything on sky.

## Upgrade Notes

- Re-integrate any masters produced by 6.2.0. Their sidecars are refused by this build and
  their pixels are not trustworthy (see Migration And Compatibility).
- If you rely on unattended weather safety, confirm your `fail_open` / `fail_closed` setting
  before the first unattended night on this build.
- Android installs upgrade in place, provided the release was signed with the permanent
  keystore.

## Rollback Plan

- Reinstall `6.2.0` from its GitHub release. The v59 schema is forward-only: a 7.0.0 database
  will not open on 6.2.0, so restore the pre-migration backup the upgrade wrote if you roll
  back.
- Captured frames are never modified by an upgrade or a rollback.
