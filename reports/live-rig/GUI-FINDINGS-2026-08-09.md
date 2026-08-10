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
