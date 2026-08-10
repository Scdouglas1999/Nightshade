# Desktop GUI drive — 2026-08-09

Driven with `tools/ui_audit/drive_linux.py` against the release Linux bundle built from
`a43145612` (all of tonight's fixes), scratch profile, softpipe on a private X server.

Why this exists: everything earlier tonight went through the headless HTTP API. The desktop GUI was
never launched, and it has its own start path — the `hasInEditorSequence` branch of
`handleSequencerStart`, plus `SequenceExecutor.start()` — that the API drive never touches.

Findings are numbered G1, G2, ... to keep them apart from the API-side L-series.

## G1 — Back on onboarding step 1 is inert but announces itself as actionable *(minor, accessibility)*

Step 1 of 13. `Back` renders in the secondary/outline style and clicking it leaves the wizard on
step 1 — correct behaviour. But the accessibility tree exposes it as a plain `button: Back` with no
`DISABLED` state, so a screen-reader user is told there is somewhere to go back to and gets silence
when they act on it. Sighted users have the visual hierarchy to fall back on; that is exactly the
cue a screen reader does not carry.

The fix is `onPressed: null` (or `enabled: false`) on the first step rather than a handler that
returns early.

## G2 — the onboarding driver rows are live, and announce themselves as disabled with no state *(fixed)*

Read straight off the running app's accessibility tree at step 2 of 13:

```
panel: Native
Direct SDK connection where the release includes the required vendor library [DISABLED]
panel: Alpaca
ASCOM Alpaca over network. ... [DISABLED]
panel: INDI
INDI protocol through a reachable INDI server. ... [DISABLED]
panel: Sim
Simulated device where that workflow is enabled for testing [DISABLED]
```

The screenshot shows Native/Alpaca/INDI **checked** and Sim unchecked, and clicking the Sim row
toggled it on. So all four are live, three are selected — and assistive technology is told the
opposite of both facts: no checked state at all, and `DISABLED`, which the harness only prints for a
node that is interactive *and* lacks `enabled`/`sensitive`. (Plain labels elsewhere in the same tree
carry no such flag, and `button: Back` carries none either, so this is specific to these rows.)

**Cause.** `_DriverTile` is a bare `InkWell(onTap:)` wrapping a `NightshadeCheckbox`. `InkWell`
publishes a tappable, focusable semantics node that never sets `isEnabled`, and that node shadows the
checkbox's own — correct — `checked`/`enabled` semantics. The checkbox component is not at fault; it
is simply not the node assistive tech reaches. This is the same class as the design-system switch and
checkbox work earlier in the campaign, on a surface that pass did not cover.

**Fix.** Declare the row itself: `Semantics(container: true, checked: selected, enabled: true,
label: '<name>. <description>', onTap: onToggle)`, with the inner row wrapped in `ExcludeSemantics`
so the name is not read twice and there is one tap target rather than two competing ones. Pointer and
keyboard behaviour are untouched.

**Worth noting for the rest of the app:** any bare `InkWell` used as a control has this same
signature. This fix addresses the surface that was reproduced; a sweep for the pattern is warranted.

## G3 — fifteen live controls on one screen announce themselves as disabled *(systemic; root cause fixed)*

Counting `DISABLED` flags on the Sequencer screen's accessibility tree gave **15**, including every
one of the primary tabs:

```
Builder [DISABLED]      Templates [DISABLED]     Sequences [DISABLED]    History [DISABLED]
Tab 1 of 3 [DISABLED]   Tab 2 of 3 [DISABLED]    Tab 3 of 3 [DISABLED]
panel: Target [DISABLED]  panel: Imaging [DISABLED]  panel: Science [DISABLED]   ...
```

All of them work — I navigated the app by clicking them. The harness only prints `DISABLED` for a
node that is interactive **and** lacks `enabled`/`sensitive`, so this is not a labelling nit: a
screen reader is being told the app's main navigation is dead.

**Root cause, and it is one line.** `Semantics(button: true, …)` publishes
`SemanticsFlag.isEnabled` **only when `enabled` is passed**. `button: true` on its own leaves the
flag unset, and AT-SPI reads an interactive node with no enabled state as insensitive.
`AdaptiveTabBar` — used for the tab strips across the app — declared its tabs and its scroll
affordances exactly that way.

Fixed in `adaptive_tab_bar.dart` (both the tab button and the edge affordance), then swept the rest
of the design system and app for the same shape: five more sites in `error_dialog.dart`,
`tutorial_overlay/tooltip.dart` and `atlas_coverage_overlay.dart`. A regex over every
`Semantics(...)` block containing `button: true` and no `enabled:` now returns zero.

G1 and G2 are the same *symptom* from a different cause — a bare `InkWell` publishing a focusable
node with no enabled flag — which is why the driver rows and device rows needed their own container
semantics rather than this one-word fix.

## G4 — a pre-flight error told a desktop user to send an HTTP request *(fixed)*

Verbatim from the Pre-Flight Validation dialog:

> No image output directory is configured. Captured frames cannot be saved. Configure
> **imageOutputPath** in Settings → File Output (or **PUT /api/settings**) before starting a
> sequence.

An internal field name and an HTTP verb, in a dialog on a desktop app. Neither is something the
reader can act on, and both invite them to think they are missing a step. The issue's own
`resolutionHint` already said the useful thing — "Configure an image save location in Settings →
File Output" — so the description now just states the consequence in plain terms. A sweep for other
`GET|POST|PUT /api/...` strings in user-visible copy found none; the remaining hits are doc comments.

## G5 — a target the app refuses to run calls itself "Ready" *(fixed)*

Same screen, at the same moment: the target card read

```
New Target
RA Not set    Dec Not set          <- amber, correct
Ready · 10 planned exposures · 10m  <- the status chip
```

…with the card's own red blocking-issue dot in the corner and pre-flight refusing the run with
"Target Coordinates Not Set". Three parts of one card, and the summary chip contradicted the other
two.

The chip is derived from the node's *execution* status, so everything that has not run yet lands on
the default arm and prints "Ready". That is the right word for a target that has not started and
could; it is the wrong word for one the app will refuse. It now reads **"Needs coordinates"** when
the same `targetCoordinatesUnset` predicate the coordinate row already uses says so.

Small, but it is the L46 family: a surface asserting a state the app has itself determined is false.

## G6 — with no observing location, the app tells the executor it is at 0°N 0°E *(P1 for an unattended night; fixed)*

The most consequential thing the GUI drive turned up, and it is invisible from the API.

The profile had **no observing location**, and the app said so in three places — "Set an observing
location for twilight times", "Set location in Settings" on the altitude chart, and the readiness
panel's "No observing location set". Then it started a run:

```
INFO Updating sequencer location: lat=Some(0.0), lon=Some(0.0)
INFO Trigger fired: Altitude Limit (altitude_limit) - NextTarget
WARN Trigger fired: Altitude Limit (altitude_limit) - action: NextTarget
   ... once per 60 s cooldown, for the whole run (6 firings observed)
```

`sequencerUpdateLocation` takes **non-nullable** doubles, so an unconfigured site cannot be expressed
as "unknown" — it is pushed as a real place in the Gulf of Guinea. Vega, the target I had entered,
sits below 30° from the equator at that hour, so the always-armed altitude trigger computed a
perfectly correct altitude for somewhere the telescope is not and voted `NextTarget`. With a single
target the run survived; **with more than one, every target would be skipped in turn**, and the run
report would say the sky was too low.

**The Rust side was already written for this** and never got the chance: it computes an altitude only
when RA, Dec, latitude *and* longitude are all present, returns `false` from the altitude condition
when altitude is unknown, and carries a one-shot *"altitude triggers are dead until location is
supplied"* warning. That warning never fired in the log — because Rust never saw the absence.

**Fix.** Withhold the push when no site is configured, using the same `!= 0.0` test
`_startNativeExecution` already applies to the higher-level `setLocation` two hundred lines earlier;
log a warning naming what stays inactive. The mid-run watcher gets the same guard, so *clearing* a
location cannot arm the trigger either.

**A note on the test, because the first version of it was worthless.** It passed with the fix
reverted. Two reasons, both worth remembering: the harness's settings provider is still loading
unless you `await appSettingsProvider.future`, so the push was skipped for an unrelated reason; and
`dart format` had reflowed the guard across three lines, so the string replacement I used to revert
it silently matched nothing and I was "testing" the unmodified file. The test now asserts the
settings are *loaded and zero* before starting, and with the guard genuinely removed it fails.

## The editor start path works — which is what made the headless gap a gap

The run I built in the GUI (Target → Take Exposures, 10 × 60 s, Vega) completed, and the bookkeeping
the headless path was missing all night is simply present here:

```
frames on disk        10
captured_images       10
imaging_sessions      id=1  "New Sequence"  total=10  successful=10  status=completed
sequence_runs         1
```

That is the positive result behind L29: `SequenceExecutor.start()` was always doing this correctly,
and the appliance's `load -> start` branch was the outlier. It now does the same things, and this run
is the reference the fix was matched against.

Also observed working, unprompted: the pre-flight refused an empty sequence and named why; the disk
check did real arithmetic ("You have 7.60 GB free; this run will consume ~0.04 GB; 7.56 GB will
remain"); the target-coordinates rule described the actual consequence ("would point the mount at
that spot in Pisces and record every frame under it as 'New Target'"); the toolbar locked
sequence-editing actions during the run and said so in their tooltips; and the Properties panel went
read-only while running.

## What this drive did not cover

Named plainly, because the drive was one session on one screen size:

* **Imaging, Guiding, Weather, Plan Tonight, Analytics** — navigated past, never operated.
* **Mobile and the web dashboard** — untouched today.
* **Windows** — the whole drive was Linux/softpipe. Rendering and native dialogs differ.
* **Resize, small windows, keyboard-only navigation** — one 1920×1200 window throughout.
* Onboarding steps 4–13, and the file-picker dialogs (I typed paths instead).
### G6 corroborated twice more by the session report

The report that auto-opened when the run finished carried, unprompted:

```
Warnings: Meridian flip for "New Target" was aborted after 0 attempt(s): ... target 'New Target'
          altitude is -4.7° which is below the minimum 10.0°. ... The mount was NOT flipped.
Mount / operations:  Trigger fires 12
```

Vega at **-4.7°** is Vega seen from the equator, and twelve trigger fires in a ten-minute run is the
60-second altitude cooldown firing throughout. So the Null Island location did not just arm the
altitude trigger — it also drove the meridian-flip decision, which refused a flip for a target that
was in fact high in the sky. Both are closed by the same fix.

Worth recording separately: the report's own arithmetic is exact. Wall clock 10m 3s, integration
10m 0s (10 × 60 s), downtime 3s, effective imaging 99.5% — 600/603 to the decimal — and frames
10/10 accepted with HFR 2.23 / FWHM 4.45 / 35 stars per frame.

## G3 continued — the sweep needed three passes, and the first two were wrong

Worth recording as method, not just result.

**Pass 1** — regex over `Semantics(...)` blocks containing `button: true` with no `enabled:` — found
5 sites. Fixed them, rebuilt, relaunched, and the Sequencer's `DISABLED` count went **15 → 11**.

**Pass 2** — widened the regex to any interactive role or handler — found 4 more, and then reported
zero remaining. That "zero" was false: the regex only balanced one level of nested parentheses, so
every `Semantics(` whose child was a deeply nested widget tree (which is most of them) fell outside
the match entirely. `sub_tab_button.dart` — the Nodes/Snippets/Queue tabs I could see flagged in the
live tree — was invisible to it.

**Pass 3** — a line-window scan instead: for each line containing `Semantics(`, look at the next 14
lines for a state/role flag and for `enabled:`. Found **18** more across 13 files, including
`nav_item.dart` (the app's primary navigation), `sub_tab_button.dart`, `pill_tab.dart`,
`status_pill.dart`, `nightshade_card.dart` and the mobile dashboard.

The bulk insertion then landed `enabled: true` inside three `MergeSemantics(...)` constructors, which
do not take it. The analyzer caught all three immediately — which is the argument for running it
after a mechanical edit rather than trusting the edit.

Measured, not asserted: the running app's `DISABLED` count on the onboarding screen went from 4 to
**0**, and the fix is what the relaunched build shows.

## G7 — every sequencer frame stored a NULL quality score, so grading graded a constant *(P1; fixed)*

The Analytics gallery, after the clean ten-frame run:

```
Captured Images:   Good: 0    Needs Review: 10    Poor: 0
every tile:        "65 score", HFR 2.2, badge NEEDS REVIEW
```

Ten frames from a healthy run, every one flagged for review and not one "Good". Reading the database
explains it:

```
sqlite> select hfr, star_count, quality_score, eccentricity from captured_images limit 1;
        2.2388   35   NULL   0.2296
```

**`quality_score` is NULL on every sequencer-captured frame.** `FrameQualityAssessmentService` opens
with `image.qualityScore ?? 75.0`, so the assessment was of the fallback constant, not of the frame;
penalties took 75 to 65, and 65 sits under the service's `advisoryScore < 70` line, which is why the
verdict was unanimous.

The asymmetry is the defect. `ImagingService`'s ad-hoc path (Imaging screen snapshot/loop) computes a
score and stores it. The **sequencer** path — every frame of every unattended night — passes `hfr`,
`starCount` and `eccentricity` to `insertSequenceFrame` and simply never passes `qualityScore`, even
though the DAO has taken that parameter all along.

**Worse than a wrong label.** A sharp frame and a soft one scored identically, so anything that ranks
or rejects on quality — stack frame selection, auto-reject, "best frame" — was ranking a constant.

**Fix.** One shared `computeFrameQualityScore` (new `frame_quality_score.dart`), used by both paths:
the sequencer now stamps a real score, and `ImagingService._calculateQualityScore` delegates to the
same function so they cannot drift apart again. A missing background/noise component — the sequencer
event carries neither — is *omitted and the weights renormalised*, not scored zero; counting an
unmeasured component as zero would punish every sequencer frame for a number nobody took, which is
the same mistake wearing a different hat. A frame with nothing measurable returns NaN and stores
NULL, so the service's fallback still applies where it honestly should.

Weights and bands are lifted verbatim from the existing implementation. **Deliberately not retuned**:
making the two paths agree is one change; deciding what "Good" ought to mean is a separate question,
and the pre-existing comment in `frame_quality_assessment_service.dart` — "observed on real captures
scoring 64-66 with healthy HFR (2.5px) and 200 stars" — says someone has already met the threshold
question on real data. That one is the owner's to settle.

Six tests, including the live-rig frame's own numbers and the discrimination property.

## G8 — the location path, proven end to end in the GUI

Setting latitude 39.9719 / longitude -75.3576 in Settings → Location, with nothing else touched:

| before | after |
|---|---|
| status bar `LST --:--:--` | `LST 20:46` |
| Weather: "Location Not Configured … configure your location in Settings" | (radar unblocked) |
| Plan Tonight: "Location not configured … before using the planner" | `AUTOPILOT WILL RUN — New Target — Live scheduler pick, what the rig would slew to next (score 3.63)`, plus a Night Outlook listing NGC7056 with altitude |

Three screens that were each honestly refusing to guess now compute. This is the other half of the
G6 story: the app is careful about an unset location everywhere a human can see, and the only place
that quietly substituted (0, 0) was the push into the executor.

## G9 — the planner's filter row is live and announces itself disabled *(fixed)*

With the planner working and returning scheduler picks, all six filters — Type, Constellation,
Magnitude, Size, Alt now, Moon — plus Sort still read `[DISABLED]` in the accessibility tree.
`_ControlChip` is another bare `InkWell`: focusable node, no isEnabled, and no on/off state anywhere
in the subtree, so a screen-reader user is told the filter row is dead and is never told which
filters are applied. Given a container `Semantics` with `button`, `enabled` and `selected: active`.

## G3 pass 4 — wrapping an InkWell in `Semantics` does not fix it, and I verified the first one wrong

Two corrections, both found by measuring the same screen before and after instead of a different one.

**The mis-verification.** I reported the onboarding driver rows as "4 → 0". That number came from the
landing screen *after a relaunch*, where the app had resumed past onboarding and was showing the
Continue Session dialog. I had counted a different screen. The driver rows were still broken.

**Why the fix did not work.** Wrapping a bare `InkWell` in a new `Semantics(...)` leaves the InkWell
publishing its **own** node — focusable, no `isEnabled` — alongside the wrapper. AT sees both, and
the flagged one is still there. Measured after a genuine rebuild+relaunch: Plan Tonight still 8,
Sequencer still 11, tabs still `[DISABLED]`.

The working pattern is `InkWell(excludeFromSemantics: true, …)` inside the wrapper, so the container
is the only node. That is different from the `AdaptiveTabBar` case, which already *had* a `Semantics`
node and only needed the `enabled` field — which is why pass 1 genuinely moved 15 → 11 and this did
not.

**Verified properly this time**, onboarding step 2 on a fresh profile:

```
before:  panel: Native
         Direct SDK connection where the release includes ... [DISABLED]

after:   check box: Native. Direct SDK connection where the release includes ... [ON]
         check box: Alpaca. ASCOM Alpaca over network ...                       [ON]
         check box: INDI. INDI protocol through a reachable INDI server ...     [ON]
         check box: Sim. Simulated device where that workflow is enabled ...    [off]
```

Role, label and state, all correct, zero `DISABLED` on the step. Plan Tonight went **8 → 2** by the
same change.

**Reverted as ineffective:** the `Semantics(enabled: true)` wrapper around the sequencer toolbox
`TabBar`. Flutter's own `Tab` publishes the "Tab N of 3" node from inside `TabBar`, and an ancestor
`Semantics` does not merge into it — the flag survived the rebuild. `TabBar` exposes no
`excludeFromSemantics`, so this is a framework limitation rather than something to paper over. Left
as a known remainder rather than a fix that fixes nothing.

**Known remainders**, all measured, none claimed fixed: the framework `Tab` nodes (3), the node-palette
category headers (5), `Sort: Score` on the planner, and a few status chips such as `0 connected`.

## Onboarding steps 2-8, walked on a fresh profile

Zero `DISABLED` on every step after the semantics fix, and the wizard behaved correctly at each
gate I tried to break:

* **Step 3 with no camera selected.** Six Next presses did nothing — which I initially read as an
  inert button. It is not: `_validate` returns *"Pick a camera to continue, or use 'Skip onboarding'
  to set it up later"* and the wizard renders it in a notice band above the footer, with a dismiss.
  Deliberately not a snackbar, per the comment at the call site: *"a snackbar covers and intercepts
  the very buttons the user needs to act on the message."* My misread, recorded because it is the
  second time on this drive that a screen looked broken and turned out to be right.
* **Driver status chips** on the camera step read `Native (0) ✓`, `Alpaca ⚠`, `INDI ⚠`, `Sim (1) ✓` —
  the two unreachable backends are marked rather than silently contributing nothing.
* **Step 8, optical train, with deliberately wrong input.** I mis-aimed and typed 1000 into Aperture
  and 200 into Reducer / Barlow. The form caught it: inline `Must be between 0.1 and 10.` under the
  reducer, and all three Computed values — Effective focal length, Focal ratio, Image scale — read
  **"Check your inputs"** instead of deriving a number from nonsense. The empty pixel-size field
  reads *"Not in the camera library — check your camera's datasheet"*.

That last one is the behaviour the rest of this report has been asking for, arrived at without
prompting: refuse to compute rather than compute something false.
## Phone-width reflow (420×900) — checked, clean

Resized the running window from 1920×1200 to 420×900 mid-wizard:

* the step sidebar collapses to a progress bar with "Step 8 of 13 — Optical train";
* fields stack full width, Next/Back stack vertically;
* no overflow, no clipping, no horizontal scroll, and the long placeholder ellipsises
  ("Not in the camera library — check your ca…") rather than spilling;
* the notice band and the "Check your inputs" computed values both survive the reflow.

One nit not raised as a finding: the inline `Must be between 0.1 and 10.` under the reducer is
transient — it is gone at both widths once the field loses focus, leaving the out-of-range value
committed. The form still refuses to compute and the notice band still names the missing focal
length, so the invalidity is surfaced; only the specific range hint is short-lived. Recorded rather
than claimed, because I did not establish whether that is focus-scoped by design.
## G10 — my own accessibility change broke a test, and my first count of the damage was wrong *(fixed)*

I reported "41 failures, all Windows-captured goldens" from a **partial** run. The completed suite
says **3,056 passed, 42 failed**, and classifying every one of the 42 by name:

* **41** are golden pixel diffs — `Pixel test failed, 13.39% / 21.41% / 75.00%` — the
  Windows-captured goldens that have never matched on Linux. Checked individually, including the
  three `imaging_landscape_capture` and three `planner_fold_cover` cases that did not look like
  goldens from their names but are.
* **1** was a real regression from today's work:
  `settings_sidebar_keyboard_test: sections and group headers announce themselves as buttons`.

`matchesSemantics` treats every flag you do not list as an assertion that it is **absent**, so by
omitting `hasEnabledState`/`isEnabled` the test was pinning the pre-fix behaviour — asserting that
the settings sidebar must NOT report an enabled state. That is precisely the defect: the whole
sidebar announced as insensitive. The expectation now requires the flags instead of forbidding them.

Two lessons, both about my own claims rather than the app:

1. **Do not classify a test run before it finishes.** The partial log was one failure short and I
   generalised from it.
2. **A semantics matcher is a whitelist.** Adding a correct flag will fail any `matchesSemantics`
   that did not anticipate it, and the failure looks like a regression when it is the test encoding
   the old behaviour. Read the diff before assuming either way.
## Analytics sub-tabs — all six walked, clean

Session, History, Projects, Equipment Stats, Science and Diagnostics on a fresh profile: **zero
`DISABLED`** on every one, and each renders its own honest empty state rather than a zero or a blank
panel — "Waiting for the first captured frame", "No session history", "No targets available for
project tracking yet", "No data", "Solve health appears once light frames start arriving", "No story
yet for this session — events appear as the Narrator interprets your data".

One near-miss worth recording as method: the tabs appeared to render **one tab behind** what I
clicked. Clicking the same tab twice returned identical content, which ruled out a lag — my
`click-xy` was landing one tab to the left the whole time. Third time on this drive that a suspected
defect was my measurement rather than the app.

## Known accessibility remainders — measured, root-caused, deliberately not "fixed"

After the sweep, these still read `[DISABLED]` in the live tree. Each was checked; none is guessed:

| nodes | widget | why it is left |
|---|---|---|
| `Tab 1/2/3 of 3` (Sequencer toolbox) | Flutter `TabBar` → `Tab` | the framework generates the node inside `TabBar`; an ancestor `Semantics` does not merge into it. Proven: my wrapper survived a rebuild with the flag intact, so it was reverted. `TabBar` exposes no `excludeFromSemantics`. |
| `Overlays`, `G100`, `Light`, `1x1` (Imaging) | `NightshadeDropdown` → Flutter `DropdownButton` | same shape — the button node comes from the framework. Fixable in principle by wrapping and excluding, but that is the pattern that needed three attempts to get right on `InkWell`, and I have no budget left to build, relaunch and verify it. An unverified accessibility fix is worth less than an accurate note. |
| node-palette category headers (`Target`, `Imaging`, `Science`, `Guiding`, `Mount`) | expansion headers | not yet traced to a widget. |
| `Sort: Score`, `0 connected`, `0 nodes`, `1` | status chips / sort control | not yet traced. |

The pattern to apply, established and verified on three widgets today: give the row a container
`Semantics` with `enabled`, and put `excludeFromSemantics: true` on the inner `InkWell` so it stops
publishing a second, unflagged node. Verify by counting the **same screen** before and after a
rebuild — not a different one.

## Final test position for this drive

`nightshade_app` re-run after the one real regression was fixed: **41 distinct failing tests, 40
distinct goldens named, zero non-golden failures** — classified by name rather than by eyeballing the
tail. Every remaining failure is a Windows-captured golden diffing on Linux.
## Open question, not a finding — Guiding "Connect" with no PHD2 running

The Guiding screen renders correctly with nothing attached: `PHD2 Disconnected`, `Stopped`, an empty
guide graph with `RA — Dec — Total —`, "Connect a guider to acquire a guide star", and a
`Not Calibrated` badge explaining "PHD2 will calibrate your mount automatically when you start
guiding." Start / Pause / Loop Exposures / Auto Select / Deselect / Brain Settings are all present.

Pressing **Connect** with no PHD2 process running produced no visible change and **no log line
whatsoever** — the log's last entry is an unrelated discovery sweep from seconds earlier, and the
whole session contains only five `guider|phd2` mentions.

That *looks* like a button that fails silently, which would matter on an unattended rig. I am not
recording it as a finding because I could not confirm the click landed: my `click-xy`/`click-img`
coordinates have been wrong three separate times on this drive, and one of those produced a
convincing phantom (the Analytics "tabs lag by one"). Establishing this needs a confirmed hit on the
button — a distinctive log line, or a state change from a control adjacent to it — and I ran out of
budget before I could get one.

Left as the first thing to settle on the next drive, with the method: click, then prove the click
landed before interpreting the absence of a reaction.
### RESOLVED — the Guiding Connect question was my observation window, not the app

Settled by proving the click landed (the Brain Settings toggle responds to the same technique and the
button is exactly at the coordinate I used) and then reading the tree **immediately** instead of ten
seconds later:

> PHD2 connection failed: PHD2 is not running and could not be launched automatically. Install PHD2
> or set Settings → PHD2 Guiding → PHD2 executable path.

Specific, actionable, and it names the exact setting to change. My earlier "no visible change" was a
snackbar that had auto-dismissed before I looked. **Fifth** time on this drive that a suspected
defect was my measurement.

One genuine residual, much smaller than the thing I suspected: the failure leaves **no log line**.
The snackbar is the only trace, so on an unattended rig — or for anyone who looks away for four
seconds — a failed guider connect is forensically invisible afterwards. Worth a `logger.warning` in
`connectPhd2`'s catch; recorded rather than changed, because I cannot rebuild and re-verify within
budget and a one-line unverified change is how the last three regressions started.
## G11 — the Settings switches expose no on/off state *(measured; cause narrowed, not fixed)*

```
Settings → General:   toggle button: Start minimized          (no state)
                      toggle button: Auto-connect equipment   (no state)
                      toggle button: Confirm before closing   (no state)

Imaging:              toggle button: Stretch            [off]
```

The screenshot shows those three in genuinely different positions — Start minimized off,
Auto-connect on, Confirm before closing on — so a screen-reader user is told there are three switches
and never which way any of them points. "Auto-connect equipment" in particular decides whether a rig
grabs its hardware on launch.

`NightshadeSwitch` itself is correct — `Semantics(toggled: value, enabled: isEnabled, onTap:)`, with
a comment saying "the enclosing row supplies the accessible label; this node supplies the switch
state". And the identical component on the Imaging screen *does* publish `[off]`. So the state is
being lost between the switch and the tree on this surface only, and the settings rows are wrapped in
`MergeSemantics` — the first place to look.

Not fixed. Every semantics change today needed a rebuild and a same-screen re-measure to tell a fix
from a no-op, twice I got that wrong, and I do not have the budget left to do it properly. A narrowed
cause someone can act on beats a fourth unverified attempt.
## Imaging sub-tabs — all seven opened, clean

Capture, Camera, Focus, Guiding, Mount, Rotator, Stack and Annotations each render their own panel
with no blank states and no crashes: "Snapshot / Loop" controls, "Session / Captured", "Correction
settings / Auto-apply when map exists", and the honest "Connect a mount to send guide corrections."
where hardware is absent. The only `DISABLED` nodes on any of them are the four framework dropdowns
already tabled above (two on the tabs that carry no frame-type/binning control).

Recorded without naming which tab showed what: my `click-xy` label mapping was off again — sixth time
this drive — and the tabs' content clearly rotated relative to the names I assigned. What is
established is that all seven switch, all seven render distinct content, and none is empty or broken.
## Web dashboard — served and accessible-clean at the markup level

`GET /dashboard` on the appliance returns 80 KB of HTML, `<title>Nightshade Dashboard</title>`, with
**113 buttons and 263 `aria-*` attributes**. Parsing every `<button>` for an accessible name — an
`aria-label`, a `title`, or visible text content — gives **zero with no name at all**. The 14 that
carry no `aria-label` all have text content, which is the correct way to name a button.

The CSP is also tightened deliberately, with the reasoning in a comment at the top: `connect-src`
restricted to same origin plus same-origin WebSockets, replacing a `http://*:*` wildcard that "would
allow an attacker-controlled page served from the dashboard origin to relay credentials".

This is a markup-level check only — it says the buttons are nameable, not that the dashboard behaves.
Driving it needs a browser session, which is the same gap as mobile and Windows.

Auth on that surface behaves: `GET /api/sessions` with no token is **401**, and with the bearer token
`/api/sequencer/status`, `/api/system/disk-space`, `/api/sessions` and `/api/images?limit=5` all
return **200**.
### G11 root cause — the merge that bound the name dropped the state

`SettingRow` wraps every row in `MergeSemantics`, and the comment above it records exactly why:

> Without this the switch is a correctly-toggled but ANONYMOUS node: measured on the running app,
> Settings > General exposed three toggle buttons reading "off/ON/ON" with empty names, so assistive
> technology could report that something was on without being able to say which setting it was.

So the surface has been through both failure modes. **Before** the merge: state without a name
(`toggle button: [off]`, `[ON]`, `[ON]`). **After** the merge, which is what I measured today: name
without state (`toggle button: Start minimized`, no `[ON]`/`[off]`). The same component unmerged, on
the Imaging screen, still publishes `[off]` — which is what isolates the merge as the cause.

That is this campaign's recurring shape — a fix that relocates the untruth rather than removing it —
and it is worth naming as such rather than as a second independent bug.

**Why it cannot be fixed inside `SettingRow`:** the row receives `trailing` as an opaque `Widget`, so
it has no way to restate `toggled:` on the merged node. The two honest options are to give
`SettingRow` the value (a `bool? toggledState` alongside `trailing`), or to move the label into
`SettingsSwitch` so one node carries both and no merge is needed. Either is a small change with a
clear before/after test — `matchesSemantics(label: 'Start minimized', isToggled: ..., hasToggledState: true)`
would fail today and pass after.

Not attempted here: it needs the build-and-remeasure loop, and today has already shown twice that a
semantics change without that loop is indistinguishable from a no-op.
### G11 WITHDRAWN — the widget layer is correct; this was my instrument again

I wrote a root cause above blaming `MergeSemantics` for trading the state away. That was wrong, and a
widget test settles it. Pumping a real `SettingRow` with a `NightshadeSwitch(value: true)` and reading
the merged node:

```
flags: [hasEnabledState, isEnabled, hasToggledState, isToggled]
label: "Start minimized\nLaunch app minimized to system tray"
```

Both halves are present. The merge binds the label **and keeps the toggled state**; the earlier fix
did not relocate anything. What I measured in the accessibility tree — a `toggle button` with a name
and no `[ON]`/`[off]` — is therefore lost between Flutter's semantics and what the audit harness reads
over AT-SPI, not inside the app.

**Sixth measurement-caused false lead of this drive**, and the one I had gone furthest with: I had
already written a cause, an explanation of why it could not be fixed in `SettingRow`, and two
suggested designs. All of it was reasoning on top of a bad reading.

The test is kept as a regression guard
(`setting_row_toggle_semantics_test.dart`) — if a future change to `SettingRow` or `NightshadeSwitch`
drops either the label or the state, it fails at the widget layer where it is cheap to see, instead
of in an accessibility tree nobody reads.

**Consequence for the rest of this report:** every `[DISABLED]` and missing-state reading in the
remainders table is a harness observation, and at least one class of them has now been shown not to
reflect the widget layer. The fixes I landed are still right — each was verified by a same-screen
before/after in the tree AND by the semantics changing in code — but the *unfixed* remainders should
be re-checked with a widget test before anyone spends time on them.
