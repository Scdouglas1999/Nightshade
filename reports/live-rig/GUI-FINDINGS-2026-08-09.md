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

