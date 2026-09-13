# w11-mount-panel — the Imaging side panel's Mount section

Branch `agent/w11-mount-panel`, base `9c233bdd0`.

Owner's report: *"Can we fix the Mount sub tab inside Imaging as well? Basically
every single button has a truncated label due to sizing."*

## What was actually wrong

The Imaging side panel is 320px wide **including** its 44px icon strip
(`SidePanel.defaultWidth`, `stripWidth`), and the panel pads its content by 16 on
each side — 244px of content. Every other section in that rail knows this and
says so ("The SidePanel already pads its content by 16"). The Mount section did
not: it added `padding: EdgeInsets.all(24)` of its own and then wrapped each
group in a `NightshadeCard` at `EdgeInsets.all(16)`. 80 of the 244px went to
air, leaving 164 for content — and the actions were laid out as
`Row(children: [Expanded, SizedBox(12), Expanded])`, i.e. 76px per button.

A `Row` of `Expanded` children is a perfectly valid layout. Nothing overflowed,
nothing threw, nothing logged. The buttons simply ellipsised their labels, which
is the whole defect: the panel offered "U…", "St…", "Three-Point P…", "RA (H…",
"Sl…" and "S…" and nothing in the app could tell.

## The fix

Measurement, not breakpoints. What fits depends on the words the mount reports
("Start tracking" vs "Park"), on the locale and on the reader's text scale, so
no dp threshold can be right.

### `nightshade_ui` (shared: the cause is in the components)

- `measureTextWidth(context, text:, style:)` —
  `packages/nightshade_ui/lib/src/utils/text_measure.dart`. One `TextPainter`
  measurement that reads the text scale off the context.
- `NightshadeButton.measureWidth(context, label:, hasIcon:, size:)` — the width
  a button needs, from the button's **own** metrics: the same text style,
  horizontal padding, icon slot and 1px border `build` paints with, so the
  measurement cannot drift from what is drawn. The three per-size metrics moved
  from `State` getters to top-level functions so there is exactly one
  implementation of each.
- `AdaptiveColumns` / `AdaptiveCell` —
  `packages/nightshade_ui/lib/src/layout/adaptive_columns.dart`. Lays cells out
  in as many **equal** columns as their measured widths allow (the widest cell
  sets the column width, so no single cell is the one that truncates) and stacks
  them full width when not even two fit. A short final run keeps the grid's
  columns. `columnsThatFit` is the pure function and is unit-tested.

### `MountTab`

| Before | After |
| --- | --- |
| `EdgeInsets.all(24)` + `NightshadeCard(padding: 16)` per group | `padding: EdgeInsets.zero` + `PanelSection`, exactly as every sibling section in the rail (14px card padding → 216px of content) |
| Actions: fixed two-column `Row` | `AdaptiveColumns`: two-up when both measured labels fit, a full-width stack otherwise |
| `ABORT SLEW`, `ButtonVariant.primary` | `Abort slew`, `ButtonVariant.destructive`, always full width |
| `Three-Point Polar Alignment` | `Polar alignment` — what the Sequencer toolbar and the command palette already call that screen; three-point is the method chosen inside it |
| `Start Track` / `Stop Track` | `Start tracking` / `Stop tracking` |
| Caps `_StatusBadge` (bespoke box) | `NightshadeChip(tone:, dot: true)` — the chip the Equipment screen's device cards use |
| `RA (Hours)` / `Dec (Deg)` hints side by side | stacked `NightshadeTextField`s labelled `RA` / `Dec` with `h` / `°` suffixes, mono values |
| `_InfoRow` (caption label over `monoSm`) | `Readout(size: ReadoutSize.sm)` — the design system's readout, em dash for an unknown value instead of `--` |
| Pulse cross with a rigid 48px centre | the centre gap is `Flexible`; the pads themselves never shrink |
| `Responsive.isMobile(context)` decided the readout grid | the grid decides from the width it is actually given — the window size never said anything about a 244px column |

`_LabelFirstButton` is the last-resort rule: below the width `label + icon`
needs, the **icon** gives way, never the words. At every real host width the
icons are all there; the wrapper is what makes 160px honest rather than a
special case.

## The sibling sections in the same rail

Driven live at the panel's real width (release bundle, harness profile
`w11mount`, `NS_AUDIT_DISPLAY=:98`), one section at a time off the icon strip:

| Section | Found | Done |
| --- | --- | --- |
| Capture | Clean. Its buttons ("View quick captures", "Clear session") are content-sized `Align`ed, not a fixed pair. The `Save to` / `Name` **fields** show truncated values, which is a field showing a long value, not a control hiding its own name. | — |
| Camera (cooling + calibration) | **Same defect.** "Cool Down" rendered "Cool D…" in a fixed two-column `Row`; "Target temperature" broke **mid-word** as "temperatur / e" in the slider's label column. | `AdaptiveColumns` for the pair; label is "Target"; copy sentence-cased ("Cool down", "Cancel warm-up") |
| Focus | The manual step-size strip clipped `500` to "50(" — a horizontal `SingleChildScrollView` with no fade, arrow or part-visible chip to say it continued. Same defect the rotator's relative-move strip was fixed for. | `Wrap` |
| Guiding | Same fixed two-column pair (Start / Stop). At rest both fit; `Starting...` beside Stop does not at 216px. | `AdaptiveColumns` |
| Mount | The reported defect. | rebuilt (above) |
| Filter wheel | Clean — positions are wrapping chips. | — |
| Rotator | Not reproducible in the sim profile (no rotator connected, so the panel is its empty state). By inspection its Go to / Sync rows are `Expanded` **field** + content-sized button, so the button cannot truncate; the field takes the squeeze. Not the same defect. | — |
| Annotations | Clean (empty state, wrapping filter chips). | — |
| DepthLock | Clean — already `Wrap`s its button groups. | — |

Copy that is still Title Case in sections I did not otherwise touch, and so was
left for the copy pass rather than mixed into a layout fix: "Tracked Stars",
"Guider Configuration", "Step Size:", "Go To Position...", "Run Autofocus",
"Temperature Compensation", "Gain / Offset".
