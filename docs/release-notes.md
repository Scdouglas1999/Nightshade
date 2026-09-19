# Nightshade 7.1.0 Release Notes

## Release

- Version: `7.1.0` (build 28)
- Build date: 2026-09-19
- Channel: `alpha` (see `version.yaml`)
- Previous release: `7.0.0` (build 27)
- Headline: **Observatory** — one design system across every screen, and the rig defects four on-sky nights found

## Release Summary

7.1 rebuilds the interface you drive the night through, and fixes the parts of the imaging
chain that real nights broke.

The whole app now sits on the **Observatory** kit — one set of panels, wells, readouts, form
rows, fields, buttons, tabs, chips, banners and side panels in `nightshade_ui` — instead of
the eleven-screen patchwork it had grown into. Every screen was rebuilt on the sheet rather
than re-skinned.

Three new pieces of instrumentation land with it. The **Sequencer ledger** shows a twelve-hour
run as a ledger of aligned columns with folded runs, sticky ancestors and a gutter map instead
of a tree you scroll. **DepthLock** measures how deep a marked region of your target actually
is, across nights and sessions, and says what it still needs — including the negative answer,
when the calibration error floor means more hours cannot help. **Focuser backlash calibration**
measures your gear train with two scans instead of asking you for a number you do not have.

The rig fixes matter more than any of it. A sequence that died 1.5 seconds after slewing, a
polar alignment that failed every westward run, an app that froze solid on the first successful
plate solve, and a guider failure that kept exposing and then parked an attended mount — all
four were invisible to the simulator, and all four are fixed here. **On-sky validation of this
build is owed** (see Known Limitations).

## Supported Platforms

| Platform | Status | Build artifact | Verification |
| --- | --- | --- | --- |
| Linux x64 | supported | `nightshade-7.1.0-linux-x64.tar.gz` (built by `.github/workflows/release.yml`) | Every claim below was proven on this platform: full Dart and Rust suites, clippy, and the production gate set run against this tree. |
| Windows x64 | supported, **validation owed** | `nightshade-7.1.0-windows-x64.zip` (built on a Windows runner by `.github/workflows/release.yml`) | Not exercised for this candidate. No Windows build, bundle audit, golden re-capture or runtime walk was performed. The ASCOM COM-worker change in this release is a compile-level change reviewed against the STA worker contract; it has not been run. |
| Android | supported, **validation owed** | `nightshade-7.1.0.apk` | Built by CI; not installed or exercised for this candidate. |
| macOS | unsupported | — | Builds in CI's build-test matrix; not tested. |

## Supported Hardware And Drivers

Unchanged from 7.0.0 — see `docs/supported-hardware-by-platform.md`. One vendor protocol fix
lands here: the LX200 arm accepts the NYX's `+05:00` reply to `:GG#` as well as `+05`.

## New Or Changed Features

### Observatory

- One kit for panels, wells, readouts, form rows, fields, buttons, underline tabs, chips,
  banners, side panels and the night band. A control behaves the same in Settings, Guiding and
  the Flat wizard.
- One page header on every screen, with the title yielding to the actions on a phone instead of
  truncating them.
- The Observatory rail replaces the old navigation; the bottom nav stays on screen below 768 px.
- Tonight (`/dashboard`), Plan, Analytics, Weather, Equipment, Guiding, Settings, Onboarding,
  the Darkroom, the Sequencer, the polar-alignment and Flat wizards and the pairing screen were
  each rebuilt on the kit.
- The select has its own popover instead of Material's menu — the cause of menus opening
  mid-screen rather than on the button that spawned them.
- Sentence case throughout, including composed sentences and their localisation twins. Red
  night reaches the Imaging canvas and the Weather map, which were both painting off the red
  axis.

### The Sequencer ledger

- Three persisted density modes, switched from the canvas bar, from the full tree down to a
  ledger of aligned columns with collapsed rollups.
- Contiguous runs fold into one row: forty identical exposures read as one line with a count.
- Sticky ancestors keep the running branch pinned while you scroll, and the gutter maps your
  position in the whole run.
- The node inspector gained Settings, Activity and Notes tabs; switching tabs no longer scrolls
  the screen pager underneath.
- The toolbox Queue tab is now Targets, showing the sequence's own targets beside a
  saved-for-later wishlist.
- Pre-flight refuses a centring sequence when no plate solver is configured.

### DepthLock

Mark the structure you care about and a nearby patch of blank sky, pick a depth, and every
matching exposure measures that region from then on — across nights and across sessions. A goal
is one filter, on one target, with one setup.

- Done is defined by the data, not the clock.
- Each filter's goal states what it still needs, so clear sky can be allocated to the one that
  is behind. A Smart Exposure plan reads those numbers directly.
- When the calibration error floor caps how deep the region can go, DepthLock says so, names
  the ceiling, and names the two things that would actually help.

Full documentation: `docs/depthlock.md`; design notes in `docs/depthlock-design.md`.

### Focuser backlash calibration

- Two scans, one approaching from below and one from above, fitted and differenced, persisted
  per focuser, with a wizard that states the run's cost before it starts.
- A cancelled calibration reports as cancelled, not as a failure.
- The backlash model was corrected against a simulated gear train, along with the
  reversal-budget formula the code actually uses.
- **The shipped default is now zero.** An invented 350 was reaching both the settings field and
  the autofocus endpoint; only the operator knows theirs.

### Also in 7.1

- Tiered Wi-Fi positioning with per-tier consent and a stated accuracy radius; Detect location
  falls back to an internet lookup in one click.
- Camera sensor specs resolve through one chain: Framing states which tier its geometry came
  from, an override claims only what was actually changed, and the planner says a missing spec
  once rather than three times.
- The Profiles tab edits the profile you click — it previously had no detail pane at all.
- Frame-timing diagnostics report UI-isolate block time and image-cache state.
- Recovery and session reporting headline the cause rather than the last teardown failure.
- The launch-time catalog modal is retired; the Tonight checklist owns it.

## Security And Remote Access

Unchanged from 7.0.0. Two notes specific to this release:

- The recovery endpoint's new `parkAndCloseWhenRecoveryGivesUp` field is an **opt-in**: a
  client that omits it leaves parking off. The other six fields remain required, so a partial
  write is a 400 rather than a silent reset.
- The DepthLock goal endpoints sit behind the same auth as the rest of the headless API;
  unauthenticated hits return 401.

## Migration And Compatibility

- **No schema migration is required** for this release.
- **6.2.0 accumulating-master sidecars are still refused.** 6.2.0 shipped a
  stacking-normalisation defect (a background-pair OLS fit that erased stars — retention
  0.08%); v1 sidecars are refused at `MASTER_STATE_VERSION 2`. Masters and sidecars produced by
  6.2.0 remain void and must be re-integrated from frames. Your captured frames are untouched.
- **Check your focuser backlash setting after upgrading.** The shipped default is now zero. If
  you were relying on the old invented 350, run the calibration wizard rather than re-entering
  it.
- Desktop, mobile and OTA versions move together to 7.1.0+28; the release build fails loudly if
  they ever disagree.

## Known Limitations

- **On-sky validation of this build is owed.** Each rig fix below was reproduced from a
  live-rig log or a simulator fault injection and is covered by tests, but this tree has not
  been flown as a whole. The polar-alignment and slew-frame fixes in particular deserve a night
  before an unattended run is trusted to them.
- **One open TPPA question.** On 2026-09-13 the mount moved 12.1° for a 10° commanded step.
  That is not explained yet and is not a software fix in this release.
- **Windows validation is owed**: build, bundle audit, golden re-capture, and the ASCOM
  COM-worker routing change.
- **Android validation is owed**: built by CI, not installed or exercised.
- **The focuser backlash calibration has not run against a real focuser in this build.** The
  model was corrected against a simulated gear train; an EAF measured 105 steps at position
  6620 on an earlier build.
- **DepthLock has not accumulated a real target across real nights.** Its forecast, yield,
  allocation and curve paths pass against seeded data.
- SFTP password auth is deliberately absent pending a dependency decision.
- The curves operation renders read-only in this build's editor.
- `denoise` on very large RGB masters has a high peak-memory profile.
- With no observing site configured, the default altitude trigger skips targets; the run
  outcome states it.
- Weather safety is fail-closed by default: with no weather device and an API that has never
  been fetched, an unattended rig will park. Set `fail_open` if that is not what you want.

## Fixed Issues

415 commits since `v7.0.0`. The rig defects, each invisible to the simulator:

- **The slew validator killed every sequence 1.5 s after it started.** It compared a J2000
  target against an of-date read-back from the mount. Arrival is now validated in the mount's
  own coordinate frame.
- **Polar alignment failed every westward run.** The rotation-axis fit picked the antipode, so
  the correction pointed the wrong way. The fit is hemisphere-consistent, Dec is re-read per
  step, and TPPA frames are solved hinted from the mount on a budget that fits between steps
  instead of a blind 30 s solve. Use a 30° step and bin 2.
- **The app froze on the first successful plate solve.** The annotation pipeline read the
  896 MB GLADE+ catalogue line by line on the UI isolate. It is off the UI isolate; the star
  matcher is bucketed instead of quadratic; an image-texture leak went with it.
- **A guider failure kept exposing, then parked an attended mount.** The imaging train is
  arbitrated so exposures stop when the guider is dead, and parking is an explicit opt-in.
- **A failed INDI reader recovery wedged the client out of ever recovering.** One failed
  reconnect left the reader marked `Restarting` for the life of the client, so the heartbeat
  never tried again and a server that came back stayed dead to the app. Found by this
  release's integration.
- **Thumbnails decoded full-resolution FITS on the UI isolate**, never reading the sidecars and
  never sizing the decode to the cell.

Other groups:

- **Autofocus**: best focus lands from below and is verified with a real frame; the MAD outlier
  filter was deleting the focus region on clean sweeps; a symmetric model gets a symmetric
  sample; star counts report what was detected rather than the brightest-N cap.
- **Equipment**: profile menus opened mid-screen rather than on their button; ASCOM mount site
  and time route through the COM worker rather than the `RwLock` guard, and the app asks which
  way to reconcile them on connect.
- **Performance**: the mount position poll no longer repaints the whole window; the status
  bar's selection is scoped; the dashboard has repaint boundaries.
- **Observatory review waves** closed the layout, narrow-window, sentence-case and
  retintable-glyph findings raised while driving the merged build.

## Verification Summary

On Linux, against this tree:

- Full Dart test suite across 11 packages, 0 failed
- 3,039 Rust tests, 0 failed
- `cargo clippy --locked --all-features --workspace --all-targets` with CI's deny list
  (`-D warnings -D clippy::result_unit_err -D clippy::await_holding_lock
  -D clippy::undocumented_unsafe_blocks`), 0 warnings
- Analyzer rollup: 0 errors, 0 warnings, 0 critical warnings, production and all
- Behavioural audit: 0 open, 0 unregistered. The register is keyed by `file:line`, so this
  release's merges orphaned 47 rows whose findings had simply moved; those were re-pointed with
  their reasoning intact rather than re-registered, and the 12 genuinely new sites reviewed and
  registered individually
- Runtime placeholder gate, fail-closed policy gate, dependency hygiene, version consistency
  (plus self-test), bridge-boundary audit (plus self-test): all green
- Cargo duplicate-versions baseline: identical to the committed baseline
- `cargo deny check licenses --all-features`: pass
- Constellation hub: `dart analyze --fatal-infos` and `dart test` both pass
- `dart format` and `cargo fmt --check`: clean

Not run for this candidate: Windows runtime, Android runtime, on-sky.

## Upgrade Notes

- Desktop, mobile and OTA versions are pinned together at 7.1.0+28.
- Re-integrate any master produced by 6.2.0.
- Re-check the focuser backlash setting; the default changed to zero.
- No database migration is required.

## Rollback Plan

The previous release is `v7.0.0` (build 27). Its artifacts remain published on the GitHub
release page. No schema migration runs in this release, so a rollback to 7.0.0 needs no
database restore — reinstall the 7.0.0 bundle over the top.
