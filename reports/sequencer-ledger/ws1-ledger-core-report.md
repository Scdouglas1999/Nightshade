# WS1 — Ledger density mode (core) — report

Workstream: `ws1-ledger-core`. Branch `agent/ws1-ledger-core`, base commit
`23147bf0a` (verified via `git rev-parse HEAD`; the tree was already on it — no
checkout needed). Spec sections delivered: **1 (density modes), 2 (ledger row
anatomy), 3 (rollup summaries)** and the canvas-bar density control. Sections
4–9 are other agents' and were not touched.

## What was built

### Density model — `widgets/sequencer_density.dart` (new)

- `enum SequencerDensity { comfortable, compact, ledger }`, each carrying its
  `label` and Lucide `icon` (`layoutList` / `rows` / `alignJustify`) so the
  three toolbar tiers can never drift on names or glyphs.
- `showsInlineExtras` — true only for `comfortable`; it gates every extra that
  renders *below* a row (progress panel, thumbnail strip, duration chip,
  comment line).
- `sequencerDensityPrefsProvider` — `AsyncNotifier` over `settingsDaoProvider`,
  key `sequencer_density_v1`, storing the bare enum name (the preference is a
  single value; unlike `thumbnail_strip_prefs_v1` there is no second field for
  a JSON object to hold). Missing/unrecognised values fall back to the default.
- `sequencerDensityProvider` — synchronous derived `Provider` that falls back
  to the default while the settings read resolves, so the first painted frame
  is already the mode the user keeps (no comfortable→ledger snap).
- `defaultDensity = ledger` — the point of the mode is that a night fits one
  screen; a preference the user must find first does not deliver that.
- `effectiveSequencerDensity(pref, isMobile:)` — returns `comfortable` when
  `isMobile`, so the phone builder always draws its existing rows.

### Canvas-bar control — `widgets/sequence_toolbar.dart`

Three tiers, mirroring the Timeline/Map group's existing tiering:

- **Labelled** (wide): the repo's `SegmentedControl` with the three mode
  labels inside the view-toggles group.
- **Glyph** (medium): three `NightshadeIconButton`s, one per mode, `selected`
  on the active mode, tooltips `"Comfortable density"` etc.
- **Overflow** (narrow): three `'Density: <label>'` menu entries appended after
  the toggle entries; the active entry is disabled (the menu has no checkmark
  affordance — a no-op tap is how a radio menu says "you are here").

`_densityControlWidth` (244 px) and the toggled width math (9 vs 6 glyph
buttons) account for the control, so the tier thresholds stay honest. The
control is gated on `!isPhone` — the phone builder forces comfortable rows, so
a control there would sell a mode the canvas refuses to draw.

### Ledger row — `widgets/sequence_tree/ledger_row.dart` (new `part`)

- 28 px fixed height, 26 px header, 18 px guide columns with a 1 px
  `colors.border` hairline each, `depth - 1` guides per row.
- Reserved 2 px left running-marker (blank when not running, so the name never
  shifts), 18 px chevron hit box with `AnimatedRotation`, 13 px icon in
  `nodeCategoryTint`, name in `bodySm` (w600 containers / w400 leaves, muted
  when done, line-through when disabled/skipped/cancelled), error colour for
  failed.
- Four right-aligned mono columns 70/60/74/62 px (`readoutXs`), labels
  `Filter / exp`, `Count`, `Duration`, `ETA`; a 26 px eyebrow header inside
  the scroll view top aligns with them.
- 2 px bottom progress bar: primary fraction while running, solid success when
  done, solid error when failed (the failure case is beyond the spec's list,
  but a failed ledger row has no other status stripe).
- Row states: running = primary-tint fill + marker; selected =
  `surfaceElevated` + `foregroundDecoration` ring (a real border would inset
  the content by a pixel on selection); hover fades `surfaceHover` via
  `ValueNotifier<bool>` so a pointer sweep repaints two islands per row, not
  the row's content.
- Hover-revealed kebab in permanently reserved 24 px — appearing actions that
  push the columns sideways make a ledger unreadable exactly when the pointer
  is in it. Always visible on touch.
- Full parity with `_NodeItem`: `_handleNodeSelect` tap/ctrl/shift selection,
  `SequenceTreeContextMenu` (right-click; long-press is claimed by the row's
  `LongPressDraggable` — the menu's secondary-tap path is what the widget test
  exercises), the row `FocusNode` (`skipTraversal`, focus on select), the
  collapsed-container `DragTarget`, `_DropZone`s, tutorial anchors,
  `_NodeValidationWrapper` with a reserved 22 px badge gutter, `Semantics`
  (name + summary + the four column values + state word).
- **Focus identity:** `FocusNode(debugLabel: 'sequence-tree-row')` — the same
  label the comfortable row uses, so focus tests and tooling do not have to
  know which density drew the row.
- **Narrow tier:** `_ledgerColumnsMinWidth = 420`. Below it a `LayoutBuilder`
  drops the whole column block and the header drops its labels — all-or-
  nothing, because a row that kept Duration but lost ETA would read as
  misaligned, and rows disagreeing about the columns' existence breaks the
  ledger's one promise.
- Target headers render as ledger rows in ledger mode: name + RA/Dec chips
  (`CoordinateFormat.raHm/decDm`, `compactLetters` → `05h30m`, `-05°24'`) or a
  `warning` "Not set" chip via `targetCoordinatesUnset`.

### Column values — `sequence_tree/ledger_columns.dart` (new, pure)

- `LedgerColumns` value object + `ledgerColumnsFor(node, sequence, {rollup,
  eta})`: exposure → `Ha 300s` / count / rollup / eta; `SciencePhotometryNode`
  fills capture columns identically; `SmartExposureNode` → `L R G B` / planned
  frames; container → blank filter / `plannedCaptureUnder` frames / rollup /
  eta; everything else → duration + eta only. Duration blank at zero (`<1s`
  reads as a measurement). Frame totals get a `+` when the walk is a floor
  (unbounded repeat / open-ended loop), an em dash when the only imager is
  open-ended, blank when nothing captures.
- `formatLedgerClock` — local 24-h `HH:mm`, hand-formatted so the column is
  identical in every locale.
- `ledgerNodeStarts` — folds `PreSessionSimulationResult.segments` into a
  `Map<String, DateTime>`; containers take the earliest descendant start
  (segments only exist for nodes the estimator bills). Cycle-safe.
- `ledgerEtaProvider` — one map provider over `sequenceTimelineProvider`; rows
  read their entry via `.select`.

### Rollup summaries — `sequence_tree/rollup_summary.dart` (new, pure)

`rollupSummary(container, sequence)` in precedence order:

1. Target — `<name> · Ha/OIII/SII` via `plannedCaptureUnder`
   (`integrationSecsByFilter`, excluding the `No filter` bucket); null → falls
   through so a slew-only target isn't named twice.
2. Filter run — `Ha · OIII · SII 300 s ×12 each · dither every 3`: ≥2 exposure
   children identical in everything but filter (duration, count, frameType,
   gain, offset, binning, dither), all filters named and distinct. The filter
   list runs straight into the spec (`Ha · OIII · SII 300 s ×12 each` is one
   phrase; a ` · ` there would detach the seconds from the bands).
3. Trigger group — every child a watchdog or autofocus with ≥1 watchdog;
   children described by their own `nodeSummary` text because a watchdog's
   threshold is its identity.
4. Generic — first three child names + `+k more`.

Empty container → `''`. Shown on collapsed containers in ledger and compact.

### Tree wiring — `sequence_tree.dart`, `sequence_tree/node_tree_view.dart`

- `SequenceTree.build` resolves `effectiveSequencerDensity` and threads it
  into `_NodeTreeView`; the `_LedgerColumnHeader` sits inside the scroll view
  above the tree in ledger mode.
- `_NodeTreeView` dispatches per node: ledger → `_LedgerRow` for *every* node
  type including targets; otherwise `TargetHeaderCard`/`_NodeItem` as today.
- **Crossfade** is per-row `AnimatedSwitcher` (`durationSmooth`,
  `curveStandard`, zero on `MediaQuery.disableAnimations`) keyed on the
  density — deliberately NOT one switcher around the tree: the outgoing tree
  would keep every `scrollKey`/tutorial `GlobalKey` mounted alongside the
  incoming tree's duplicates ("multiple widgets used the same GlobalKey").
  Inside the scroll key, the outgoing row holds no key the incoming one
  wants.
- Inline extras (progress panel, thumbnail strip, duration chip, comment) are
  gated on `density.showsInlineExtras` — off in compact AND ledger.
- Ledger indent is the 18 px guide column per depth; the children area adds no
  padding in ledger (padding + guides would double-indent).
- Drag feedback in ledger is a `_LedgerRow(isDragging: true)` at
  `_ledgerDragFeedbackWidth` (460 px) so the dragged row looks like the row it
  came from.

### Shared extraction — `node_item_helpers.dart`, `support_widgets.dart`,
`node_item.dart`

- `_NodeItem`'s inline kebab moved verbatim into `_NodeOverflowMenu`
  (`support_widgets.dart`) so the ledger row offers the identical menu —
  including the touch-only Enable/Duplicate/Delete entries and read-only
  "Save as Template".
- `_showSaveAsSnippetDialog`, `_getIcon`, `_getStatusColor`, the container
  type test and `NodeSummaryLine`'s category tint became free functions
  (`showSaveAsSnippetDialog`, `sequenceNodeIcon`, `nodeStatusColor`,
  `isSequenceContainer`, `nodeCategoryTint`); `_NodeItemHelpers` delegates, so
  two rows in one tree can never disagree about what a node looks like.
- `_NodeItem` gained `showInlineExtras` (default true): false suppresses the
  progress panel and comment line for compact mode. The panel's own
  persistence state machine keeps running, so switching back mid-run reveals
  the panel the run is on.

## Tests

New:

- `test/screens/sequencer/widgets/ledger_columns_test.dart` — pure: every
  node-type shape, `+`/em-dash/blank counts, zero-duration blank, clock
  format, ETA map folding incl. detached subtrees.
- `test/screens/sequencer/widgets/rollup_summary_test.dart` — pure: all four
  shapes + every fall-through (mismatched exposures, unfiltered, autofocus-
  only, empty container).
- `test/screens/sequencer/sequencer_density_prefs_test.dart` — persistence
  round-trip, unknown value → default, `effectiveSequencerDensity` mobile.
- `test/screens/sequencer/sequence_tree_ledger_mode_test.dart` — 28 px row
  extent, four headers + values, target coordinate chips (`05h30m`, `-05°24'`),
  chevron → `collapsedNodeIdsProvider` + rollup text, selection + ctrl
  multi-select + context menu (secondary tap), palette drop into expanded and
  collapsed containers, density switch hides/shows inline extras.

Adjusted (density pinned to `comfortable` — these tests assert card-row
content the ledger row intentionally omits):

- `sequence_tree_collapse_all_test.dart` (collapsed ledger rows print a
  rollup naming children, colliding with the "children are gone" assertion)
- `widgets/exposure_card_after_run_test.dart` (4 cases: inline frame tally)
- `widgets/exposure_card_wave_f_events_test.dart` (2 cases)
- `widgets/node_spinner_only_while_executing_test.dart` (3 cases: the spinner
  is card-only; ledger marks running via tint + bar)
- `widgets/node_summary_inline_edit_test.dart` (5 cases: editable summary
  chips live on the card's summary line)

Each override carries a comment saying why.

## Deviations from the spec

1. **Failure progress bar.** Spec §2 lists primary-while-running and
   success-when-complete. A failed ledger row also fills its bar `error` —
   ledger rows have no status stripe, and an unmarked failure loses the one
   outcome the operator most needs to spot.
2. **Per-row crossfade** rather than one tree-level `AnimatedSwitcher` —
   required by the registry GlobalKeys (see above); the visual result is the
   same tree-wide crossfade.
3. **Narrow tier hides columns below 420 px.** Spec requires aligned columns
   but also that narrow layouts not overflow; at ~271 px (one narrow-pane
   test) 314 px of fixed chrome cannot fit. All-or-nothing rather than
   dropping ETA first, which would read as misalignment.
4. **Kebab in reserved width** rather than appearing on hover — reserved
   rather than inserted so the columns never shift under the pointer.
5. **`sequencer_density_v1` stores the bare enum name**, not the JSON object
   `thumbnail_strip_prefs_v1` uses — one value, no object to hold.
6. **Focus `debugLabel` unified** to `sequence-tree-row` (not a ledger-
   specific label) — the label is the row's identity to shortcuts/tests, and
   density must not change it.

## Commands run

```
dart format --output=none --set-exit-if-changed \
  packages/nightshade_app packages/nightshade_core packages/nightshade_ui
```
EXIT=1 — 19 files not format-clean repo-wide; 11 are pre-existing drift on
the base commit in files this workstream does not own (`status_bar.dart`,
`mount_site_*`, `imaging_chain.dart`, weather/status-bar tests). The 8 that
were mine were formatted; a re-check of exactly my 19 touched files:
`Formatted 19 files (0 changed)`, EXIT=0.

```
cd packages/nightshade_app && dart analyze
```
EXIT=2 — the base commit is not analyze-clean repo-wide: 891 issues (7
pre-existing warnings in guiding/planner/shell/widgets tests, 884 info
lints). Re-run on the base commit: also 891 issues — **zero net new
diagnostics** from this change; my four new files report "No issues found!".

```
cd packages/nightshade_app && flutter test test/screens/sequencer \
  --concurrency=4        # TMPDIR=$HOME/.cache/ns-tmp/ws1-ledger-core
```
EXIT=0 — **+545, all passed.** (Base: 507; +38 new tests: 32 pure + 6 widget.)

Dedicated runs during development:
- `ledger_columns_test.dart` + `rollup_summary_test.dart` + `sequencer_density_prefs_test.dart`: 32/32 pass.
- `sequence_tree_ledger_mode_test.dart`: 6/6 pass.
- `graphify update .` — rebuilt graph (113554 nodes), EXIT=0.

## Left undone

- Nothing in scope. Mobile is intentionally untouched per the brief.
- The 11 pre-existing format-drift files and 7 pre-existing analyzer warnings
  outside this workstream's file list were left as-is; fixing them would edit
  files other agents may own.
