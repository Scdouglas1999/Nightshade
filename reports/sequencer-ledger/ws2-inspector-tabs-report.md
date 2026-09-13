# WS2 — Inspector tabs (Settings / Activity / Notes)

Workstream: `ws2-inspector-tabs` · spec §8 (+ the Activity-tab "frame landed" pop from §9)
Base commit: `23147bf0a` (verified `git rev-parse HEAD` at session start — matched, no checkout needed)
Branch: `agent/ws2-inspector-tabs`

## Design decisions / deviations (running log)

- **Exposure Activity layout.** The spec'd frame grid (success / primary /
  surfaceOverlay cells + `N of M done · capturing K` caption + total
  integration + thumbnail strip) IS the exposure node's activity view in the
  inspector. I deliberately do NOT also render `_ExposureProgressPanel`
  (returned by `getProgressPanelForNode` for exposures): that panel already
  contains its own frame grid and stat boxes, so stacking both would paint two
  grids carrying ~90% identical information. The generic
  `getProgressPanelForNode` covers every non-exposure leaf; the new grid
  section carries the same facts in the spec's form.
- **Frame-math duplication.** `_ExposureProgressPanel`'s
  tally > structured > parsed-string > node.count precedence is mirrored in a
  small resolver inside `node_activity_tab.dart` rather than refactoring the
  panel — the brief restricts `node_progress_panels` edits to the last-known
  factoring, and the tree-side copy is owned by another workstream.
- **Last-known persistence as a provider.** `_NodeItem`'s `_lastKnown*`
  fields/remember/forget logic is factored into
  `lastKnownNodeActivityProvider` (a `StateNotifierProvider` folding
  `sequenceProgressProvider` deltas per node id, clearing on a fresh
  `running` transition exactly like `didUpdateWidget` does). The tree keeps
  its own copy for now per the brief; the inspector shares this one.
- **Comment clearing.** `SequenceNode.copyWith(comment:)` is keep-or-replace
  (null keeps), so "no comment" is committed as `''` — the tree's italic line
  and the tab dot both check `isNotEmpty`.
- **Notes dot.** `AdaptiveTab` has no dot slot (nightshade_ui is out of
  scope), so the Notes tab label gains a `•` suffix when the node has a
  comment; `semanticLabel` announces "Notes, has comment".
- **Banner on mobile.** `_SelectedNodeBanner` is pinned at the bottom of the
  mobile sheet as well as the desktop sidebar, per "pinned at the bottom
  regardless of tab". It self-hides when the node has no issues.
- **Subtree progress** reuses `plannedCaptureUnder` for totals (all three
  capture node types) and derives "done" per node from
  `sequenceProgressProvider.nodeStatuses` + `nodeExposureTallyProvider`,
  carrying the same repeat-caveat semantics as
  `targetExecutionProgressProvider` (per-pass statuses can't scale across a
  loop repeat → completion is reported as unknown rather than fabricated).
- **Notes commit.** Multi-line field; commits on focus loss and on
  `onSubmitted` (Enter). Guarded by `canEditSequenceProvider` and routed
  through `withSequenceMutation` like every other inspector edit.
  `onTapOutside` unfocuses the field explicitly, because Flutter does not
  auto-unfocus a `TextField` when another widget is tapped — without it,
  switching tabs would drop the half-typed note silently. When the selection
  moves to a DIFFERENT node while the field holds uncommitted text,
  `didUpdateWidget` commits that text against the node it was typed on
  rather than letting it bleed onto the newly selected node.
- **Iconless tabs.** `AdaptiveTabBar` collapses labelled tabs to icons below
  480 px (`collapseLabelsWhenTight`, default on, tuned for the 4-tab page
  header). The inspector is a 300 px sidebar where icon-only
  Settings/Activity/Notes would be cryptic, so the collapse is disabled and
  the tabs are text-only (icons cost ~28 px/tab and pushed the strip past
  even 340 px, clipping "Notes" behind the scroll affordance). The bar's
  own overflow scrolling remains as the fallback on narrower hosts.
- **Pop-animation re-baseline.** When the captured count DROPS (a loop's
  next pass resets the tally), `_previousCaptured` is reset to 0 so the
  first landing of the new pass pops as well — otherwise a completed count
  of 1 against a remembered 12 would never re-arm the animation.

## Commands run (exit codes appended as I go)

- `git rev-parse HEAD` → `23147bf0a472b314da1e458384cb9cacf9d5973c` (exit 0)
- `graphify update .` → exit 0 (graph was missing in this worktree)
- `flutter test test/screens/sequencer/node_properties_panel_tabs_test.dart
  --concurrency=4` → exit 0, 11/11 (run with
  `TMPDIR=$HOME/.cache/ns-tmp/ws2-inspector-tabs`)
- `flutter test test/screens/sequencer --concurrency=4` → exit 0,
  **518/518** (507 base + 11 new)
- `dart format --output=none --set-exit-if-changed packages/nightshade_app
  packages/nightshade_core packages/nightshade_ui` → exit 1 — **pre-existing
  drift on the base commit**: the 11 unformatted files are all outside my
  file list (`status_bar*`, `mount_site*`, `weather_alert*`,
  `device_operations`, `imaging_chain`, `mount_site_reconciler*`); none are
  in my diff. Scoped to my 6 files the same command exits 0.
- `cd packages/nightshade_app && dart analyze` → exit 2, 891 issues —
  **all pre-existing on the base** (0 errors; unused-import warnings +
  deprecation infos in files outside this workstream). Scoped to my files:
  0 issues of any severity. Base count was 893; the change nets −2
  (removed a `surfaceAlt` use the notes editor would have added, and no new
  diagnostics).
- `graphify update .` (post-implementation) → see final log line below.

## Left undone

- The tree's private `_lastKnown*` copy in `node_item.dart` is deliberately
  left in place — the density-mode workstream removes it when the inline
  panels move; `lastKnownNodeActivityProvider` is the shared slot they will
  switch to.
- `getProgressPanelForNode` still declares `Widget?` though it never
  returns null; the `?? SizedBox.shrink()` at my call site is type-system
  glue only.
