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

