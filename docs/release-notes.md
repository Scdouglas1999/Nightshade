# Nightshade 6.1.0 Release Notes

## Release

- Version: `6.1.0` (build 25)
- Release candidate commit: `969bb9da09162d9363658683afaa3d36eb9562c7`
- Build date: 2026-07-30
- Channel: `alpha` (see `version.yaml`)
- Reviewer: not yet signed off — see `docs/production-readiness/final-release-signoff-evidence.json`
- Decision: pending reviewer sign-off; this candidate is a DRAFT and is not published

## Release Summary

6.1.0 is a reliability release. It closes two ship-blockers, fixes roughly 92
verified defects across twelve product areas, and makes the device simulators
capable of failing so the app's error paths can actually be exercised without
hardware.

The two ship-blockers were both silent. The database integrity check treated
any open-time SQLite error as corruption and rotated the user's database aside,
so an ordinary lock contention or permission problem destroyed a healthy
library and replaced it with an empty one; a real quarantined database was
recovered during this work with 182 captured frames intact. The mosaic project
screen never loaded at all — an infinite spinner over a rebuild loop.

Two changes alter behaviour on a real run rather than just fixing a display.
The built-in guider now carries sub-minimum corrections across frames instead
of discarding them, because the mount's minimum pulse length was acting as the
guiding dead band instead of the guider's own declared noise floor; against a
one-directional drift that parked the error at a standing offset. Separately,
the native target scorer rewarded a bright moon: `score_moon_distance` returned
a flat perfect score for anything past its distance threshold, so a full moon at
120 degrees outscored a new moon at the same separation. Both are covered by
unit tests only. Neither has been validated on sky.

## Supported Platforms

| Platform | Status | Build artifact | Verification |
| --- | --- | --- | --- |
| Windows | supported | `nightshade-windows-x64.zip` (built by `.github/workflows/release.yml` on a Windows runner) | Automated suites only this cycle. The local Windows bundle audit did NOT run for this candidate — `docs/production-readiness/windows-bundle-audit.json` reports `passed: false` with 16 required files missing, because no Windows build machine was reachable. Treat Windows as unverified for 6.1.0 until that audit is regenerated. |
| Linux | supported | `nightshade-linux-x64.tar.gz` | Release bundle built and driven headless under Xvfb during this campaign; `docs/production-readiness/linux-release-build-evidence.json` passes. |
| Android | limited | `nightshade-android.apk` (debug-signed) | Automated suites only this cycle. |
| macOS | not shipped | none | Not built or released. |

Platform capability boundaries (ASCOM COM is Windows-only, native SDK paths are
capability-gated, and so on) are listed in
`docs/supported-hardware-by-platform.md` and must match the in-app Platform
Capabilities view.

## Supported Hardware And Drivers

No new hardware was verified in this release. The supported matrix is unchanged
from 6.0.0 and remains authoritative in `docs/supported-hardware-by-platform.md`,
including the items still marked partial or unverified there (PegasusAstro
NYX-101 headless connect, ZWO EFW headless set-position, PHD2 full guide+dither
loop).

What changed instead is the ability to test hardware misbehaviour without
hardware. The simulators previously contained nine error returns across 1753
lines, every one of them a "you forgot to connect" gate — they could not model a
device that connects, answers, and then misbehaves. 6.1.0 adds a fault-injection
layer covering fifteen operation keys with triggers (once, N times, always,
after N calls, every Nth call, and a seeded reproducible probability) and
effects (driver error, the real ASCOM `0x80020009` not-implemented failure,
mid-session disconnect, delay, delay-then-error, stall, and focuser backlash).
Stall and backlash deliberately report success, because a mount or filter wheel
that accepts a command and never arrives is the failure that costs a night
precisely because nothing reports an error.

Faults can be armed in a release build without rebuilding, via the
`NIGHTSHADE_SIM_FAULTS` environment variable. A malformed specification arms
nothing and logs an error rather than silently running clean.

## Security And Remote Access

No change to the security model in this release. Remote access scopes remain
coarse-grained (`view`, `control`, `admin`) as documented in
`docs/known-limitations.md`.

One remote-access defect was fixed: the headless API advertised command/event
correlation in `/api/docs`, but no handler was ever given a correlator, so every
action response omitted its `commandId` and every emitted event carried
`correlatingCommandId: null`. The feature was entirely inert and is now wired,
with a test that asserts the wiring rather than the lookup table.

**Not verified for this candidate:** the second-device LAN/firewall smoke test
requires a real phone, tablet or second computer reaching the host through the
actual router, and no such device was available. `second-device-lan-firewall-smoke-evidence.json`
does not pass, and remote access over a real network path should be treated as
unverified for 6.1.0.

## Migration And Compatibility

- No database schema change requires user action. Existing libraries open
  normally.
- The integrity-check fix changes recovery behaviour in the user's favour: a
  database that fails to open for an environment reason (locked, read-only, I/O
  error) is now reported as an error and left on disk, where previously it was
  moved aside. Databases quarantined by an earlier build remain on disk as
  `nightshade-corrupt-<timestamp>.db` and can be inspected and restored from the
  recovery dialog, which now re-checks the file and says plainly when it was
  never corrupt.
- A single-instance lock (`nightshade.db.lock`) is taken beside the database.
  Running two copies against the same database now refuses with a clear message
  naming the holding process instead of risking contention. Set
  `NIGHTSHADE_ALLOW_MULTIPLE_INSTANCES=1` to override.
- Guiding and target-scoring behaviour changed as described in the summary. If
  you have tuned guiding aggressiveness around the previous dead-band behaviour,
  re-check it on a supervised night.

## Known Limitations

The accepted limitations for this candidate are listed in
`docs/known-limitations.md` and are unchanged in substance from 5.0.0/6.0.0.
The limitations most relevant to 6.1.0:

| Area | Limitation | Impact | Workaround |
| --- | --- | --- | --- |
| Validation | No on-sky or physical-rig validation was performed for 6.1.0. | The guider dead-band and moon-scoring changes alter real-run results and are unit-tested only. | Run a supervised night before relying on unattended guiding or automatic target selection. |
| Windows | The Windows bundle audit did not run for this candidate. | The shipped Windows archive is built by CI but was not audited locally against the required file manifest. | Regenerate `docs/production-readiness/windows-bundle-audit.json` from a real Windows build before publishing. |
| Remote | Second-device LAN/firewall access is unverified for this candidate. | Access from a phone or tablet through a real router is untested this cycle. | Perform the smoke test on your own network before depending on remote access. |
| Distribution | Windows is unsigned and Android is debug-signed. | SmartScreen and Android install warnings appear. | Verify the SHA-256 against the GitHub release. |
| Updates | Artifacts are manual-update-only; no updater executable or update server ships. | The app will not install the next release automatically. | Download and replace the bundle manually. |

## Verification Summary

| Check | Result |
| --- | --- |
| `melos run test` | 9716 Dart tests across 11 packages, 0 failures |
| `cargo test -p nightshade_bridge --lib` | 420 passed, 0 failed |
| `cargo test -p nightshade_sequencer --lib` | 694 passed, 0 failed |
| `cargo fmt` / `cargo clippy --lib --tests` | clean |
| Analyzer | 0 errors, 0 warnings (57 pre-existing infos) |
| `melos run format` | clean |
| Placeholder / high-risk audit | passes |
| Narrative-comment, stale-comment, version-consistency, oversized-file audits | pass |
| Golden image tests | excluded (`--exclude-tags golden`); goldens are Windows-captured and fail on Linux by design. Not regenerated. |
| `melos run audit:public-release-gate` | **NOT_READY** — 21 checks pass, 4 blockers, recorded in `docs/production-readiness/public-release-gate.json` |

Every fix in this release was reviewed by an independent per-area verification
pass that re-derived each root cause rather than accepting the fixer's claim.
That pass rejected 7 of 11 fix batches on first submission — the recurring
failure was relocating a defect rather than removing it (moving a hardcoded
layout threshold, matching a refresh timer to the poll period it measured,
replacing one false UI claim with another). Each was reworked until the defect
was gone. Every new regression test was mutation-checked by reverting its fix
and confirming the test fails.

## Upgrade Notes

1. Back up your database directory before upgrading. The default location is
   shown in Settings; it can be overridden with `NIGHTSHADE_DATABASE_DIR`.
2. Close any running copy of Nightshade. The new single-instance lock will
   refuse a second copy against the same database.
3. Replace the application bundle with the 6.1.0 archive for your platform.
4. Launch once and confirm the version reads 6.1.0 and your image library and
   equipment profiles are present.
5. If an earlier build quarantined your database, the recovery dialog will now
   offer to restore it and will state whether the file was actually corrupt.

## Rollback Plan

1. Close Nightshade.
2. Re-extract the previous 6.0.0 archive from its GitHub release over the
   installation directory.
3. Restore the database backup taken in step 1 of the upgrade notes, if the
   6.1.0 session wrote to it.
4. No schema migration is applied that 6.0.0 cannot read, so an unmodified
   6.1.0 database opens in 6.0.0. The `nightshade.db.lock` file is inert to
   older builds and can be deleted.
5. Report the reason for rollback against the release gate artifact
   `docs/production-readiness/public-release-gate.json` so the blocker set is
   updated before the next candidate.
