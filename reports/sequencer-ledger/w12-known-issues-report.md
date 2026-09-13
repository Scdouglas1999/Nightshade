# w12-known-issues — the known failing tests, and everything else open on this branch

Workstream `w12-known-issues`, branch `agent/w12-known-issues`, base `94f13cd6d`
(verified with `git rev-parse --short HEAD` before any edit — no detach needed).
`TMPDIR=$HOME/.cache/ns-tmp/w12-known-issues`, `--concurrency=3` throughout.

Fence: everything except `screens/imaging/tabs/*.dart`,
`screens/imaging/widgets/imaging_side_panel.dart` (agent a) and the geolocation
set — `nightshade_planetarium/.../geolocation_service.dart`,
`services/positioning/`, `screens/settings/widgets/location_settings.dart`,
`screens/onboarding/steps/site_step.dart`, `widgets/geolocation_consent.dart`,
`settings_search_index.g.dart` (agent b).

## Baselines at `94f13cd6d`

| package | tests | failing |
|---|---|---|
| nightshade_app | 4318 | **40** |
| nightshade_planetarium (`--exclude-tags golden`) | 588 | 0 |

The brief named 18 known failures. The full run found **40** in
`nightshade_app`: the 18, plus 22 more in darkroom / equipment / collaborative
sky / dashboard / planner that no brief had listed.

## Root cause of 5 of the 18: `NightshadeButton` is greedy in a loose slot

`AnimatedContainer(alignment: Alignment.center, …)` inside the button's
`Stack(fit: StackFit.passthrough)`. A `Container` that aligns its child sizes to
`constraints.biggest`, and a `Column(crossAxisAlignment: start)` hands its
children LOOSE constraints — so every button in a start-aligned Column took the
full page width. Measured on the base commit (probe, since removed):

```
COLUMN=800.0   ROW=138.8   EXPANDED=600.0     (before)
COLUMN=209.3   ROW=138.8   EXPANDED=600.0     (after)
```

Removing the `alignment` keeps both documented behaviours — the `passthrough`
comment in the same file says a button handed TIGHT constraints
(`Expanded(child: NightshadeButton(...))`) must still stretch, and it does; the
`Row`'s own `mainAxisAlignment: center` centres the label inside a stretched
box. The greedy width is what pushed the session-handoff chips, the mosaic
wizard's footer and the backup screen's Restore row below their containers'
folds, and what stretched the pairing screen's one primary to 1198 px.

## Root cause of 10 of the 18: `LayoutBuilder` refuses intrinsics

`NightshadeTextField._singleLineWell` chose `MainAxisSize`/`FlexFit` from
`constraints.hasBoundedWidth` inside a `LayoutBuilder`. `AlertDialog` measures
its content through `IntrinsicWidth` (`dialog.dart:925`), and `LayoutBuilder`
throws on every intrinsic query — so a single field anywhere inside an
`AlertDialog` took the dialog down. `git show e90e3184b:…nightshade_text_field.dart`
has the same `LayoutBuilder` at line 231, so this predates the w7 centring work
rather than being caused by it.

New `packages/nightshade_ui/lib/src/utils/field_width.dart` — `FieldWidthBox`, a
`RenderProxyBox` that resolves the same rule in `performLayout` (bounded slot →
`constraints.maxWidth`; unbounded → the child's max intrinsic width) and hands
the child a TIGHT width, so one widget tree serves both cases and intrinsics
pass straight through. Two live call sites were crashing:
`focus_panel.dart:637` (the 10 failing tests) and `sequence_toolbar.dart:1060`.

w7's centring measurements are unchanged: `nightshade_text_field_test.dart`
still passes, including `numeric, lowercase and unit ink centres on the well`
(`lowercase ink offset: 0.00 px`).

## The 18

| # | test | verdict | reason |
|---|---|---|---|
| 1 | `widgets/go_to_position_dialog_test.dart` (10) | **product** | `LayoutBuilder` intrinsics, above. Assertions all correct. |
| 2 | `sequencer/session_handoff_dialog_test.dart` (1) | **product** | greedy button width pushed the per-target `Restart` chip below the dialog's fold; no test edit needed. |
| 3 | `sequencer/widgets/mosaic_wizard_resume_test.dart` (1) | **product** | same; `Start over` sat outside the dialog. |
| 4 | `settings/backup_restore_notice_test.dart` (2) | **product** | same; the row's Restore action sat at y=1235 in a 1200 px view. |
| 5 | `settings/pairing_observatory_kit_test.dart` (1) | **product** | same; the page's one primary measured 1198 px against the test's `< 320`. The product comment at `pairing_screen.dart:112` already claimed the button was "sized to its label" — the button component made that false. |
| 6 | `settings/settings_search_query_test.dart` (1) | **test** | the page renders `GLADE+ galaxy catalog` (`view_builders.dart:326`), sentence case per the design contract; `git log -S "GLADE+ galaxy catalog"` dates it to `e90e3184b`, and the generated index matches. The test's title-cased literal is stale. Also fixed the one site still using the old spelling (`catalog_settings_screen.dart:589`, the download-progress label — the import path at :636 already said sentence case, so the same catalog was named two ways on one screen). |
| 7 | `shell/checkpoint_recovery_dialog_test.dart` (2) | **product** | `RenderFlex overflowed by 57 pixels` — the barrier-locked "Recover Sequence?" `AlertDialog` put an unbounded-length backend failure message in a bare `Column`. Content is now a `SingleChildScrollView`. |
| 8 | `nightshade_planetarium` `test/benchmark/golden_compare_test.dart` (1) | **environmental, already registered** | see below. |

### The planetarium golden gate

Already `@Tags(['golden'])` at file level with the tag declared in
`packages/nightshade_planetarium/dart_test.yaml`, so the CI command
(`flutter test --exclude-tags golden`, what `melos run test` runs) never
selects it — that package is 588/588 green under the CI command. Run
explicitly it reports 1.9–4.4 % changed pixels against a 0.20 % limit on all
five checkpoints.

Not a regression to fix on Linux: the baselines were captured on Windows at
`bd062b659` (pre-6.0.0) and ~20 commits of INTENTIONAL planetarium render
change have landed since (DSO sizes, catalog tiers, HYG depth, pointer-anchored
zoom). `docs/testing/golden-tests.md` forbids re-baselining on a non-canonical
host, which is the same policy that keeps the two Windows framing goldens out
of scope. The doc's quoted "~0.3 % changed-fraction for the planetarium gate"
is stale by those 20 commits; updated to the measured figure so the next reader
does not treat 4 % as evidence of a regression.

## The 22 failures nobody had listed

The brief's 18 were not the whole of it: the full `nightshade_app` suite on
`94f13cd6d` failed **40**. The extra 22 split three ways.

| tests | verdict | reason |
|---|---|---|
| `collaborative_sky/adaptive_modal_no_slab_test.dart` (3), `darkroom_branch_and_export_test.dart` (1), `darkroom_editor_wiring_test.dart` (2), `darkroom_screen_test.dart` (7), `darkroom_zoom_readout_test.dart` (1), `dashboard/standby_prompt_reserve_test.dart` (1) | **product** | all 15 were the same greedy-button width: overflowing columns, modals that no longer wrapped their content, cards pushed off their panes. Fixed by the `NightshadeButton` change; no test touched. |
| `equipment/profile_editor_dialog_validation_test.dart` (3), `equipment/profile_editor_reducer_round_trip_test.dart` (3) | **test** | the optics finders required `TextField.decoration.suffixText == 'mm'`, a property `NightshadeTextField` has NEVER set (`git show e90e3184b:…nightshade_text_field.dart` has the unit as a sibling `Text` in the Row; w7 moved it to `decoration.suffix`, still not `suffixText`). The finders matched nothing, so `enterText` threw `Bad state: No element` and six cases never reached an assertion. Now matched on `NightshadeTextField`'s own `hint`/`suffix`. |
| `planner/planner_screen_test.dart` (1) | **test** | `tester.getSize(find.widgetWithText(TextField, 'Search catalogs')).height` measured the Material `TextField` INSIDE the field, which is the 14 px editable slot, not the 28 px dense control. Expected 28, read 14. Now measured on the `NightshadeTextField` ancestor — the thing the assertion is about. |

And one in `nightshade_core` (`+6508 ~4 -1` on the base commit, also unlisted):
`sequence_data_classes_serde_test.dart: FilterPlan to_json_shape_uses_snake_case_and_pascal_binning`. That one found a **product** defect — see the commit below.

## Everything else

### 1. `dart format`
43 drifted files, formatted in one commit (`3eac83a72`). None in either
parallel workstream's fence — the drift is the DepthLock tree, the imaging
widgets, `title_bar.dart`, `smart_exposure_properties.dart`,
`nightshade_tooltip.dart` and three `nightshade_core` test files.
`dart format --output=none --set-exit-if-changed packages lib` → **EXIT 0**.

### 2. `FilterPlan` lost its DepthLock binding on the way out

`FilterPlan` gained a nested `depthGoal` (`DepthGoalBinding?`) without
`explicitToJson`, so `_$FilterPlanToJson` emitted `'depth_goal':
instance.depthGoal` — the OBJECT, not its map. The returned map is JSON only
by accident: `jsonEncode` rescues it through `toEncodable`, and anything else
that reads the map gets a Dart instance where the Rust side's
`Option<DepthGoalBinding>` expects an object. `AdaptiveSwapSnapshot`, in the
same generated file, already sets the flag for exactly this reason.

Fixed at the annotation and regenerated (`--build-filter` on the one output;
the 47 drift-dao `.g.dart` files build_runner deleted as a side effect were
restored, and four unrelated `.freezed.dart` files whose only diff was
re-copied doc comments were reverted to keep the diff to the defect). The
wire-shape test now pins `'depth_goal': null` and a new case round-trips an
attached goal.

### 3. Analyzer

`dart analyze packages apps` → **0 errors, 0 warnings** (from 11 warnings).
All 11 were in test code:

- 8 unused imports, dropped.
- `planner_screen_test.dart`'s `_tapCandidateAction` — dead since the test was
  rewritten, deleted.
- `mount_site_reconciler_test.dart`'s `_SiteBackend.site` and `timeThrows`:
  `UNUSED_ELEMENT_PARAMETER` because no test ever gave them, which means the
  reconciler had **no coverage of a successful site read and none of a failing
  clock read** — the two cases the card's whole purpose rests on. Both are now
  tested rather than the parameters deleted.

The analyzer-rollup gate reports `production: errors=0, warnings=0; critical
warnings: 0` → **EXIT 0**.

### 4. The CI gates

**Behavioral audit** — 46 unregistered findings on arrival.

- **21 were line shifts, not new findings**: the DepthLock work added two lines
  above every `rust_let_underscore` / `unwrap_or_literal` site in
  `sequencer/src/executor/start.rs` (all 16 moved +2), and similarly for
  `bridge/src/event/sequencer.rs`, `nightshade_bridge`'s `sequencer.dart` and
  `sequencer.freezed.dart`, and `live_stacking_provider.dart`. My own
  scroll-view edit moved `_startup_checkpoint.dart`'s probe catch 304 → 310.
  Each row was remapped by matching same-file/same-kind rows to findings in
  line order, never by text.
- **25 were genuinely new** — the DepthLock feature, which had never been
  through this gate. Each was read at its own line and registered with its own
  reason (no boilerplate): the SIP `A_/B_/AP_/BP_ORDER` guards where an absent
  card means order 0 by the FITS convention; `XBINNING`/`YBINNING` where an
  absent card means unbinned; `NFRAMES` where the 0 is what makes the next
  line's rejection fire; the two `let _ = reply.send(..)` arms whose receiver
  is gone because the caller cancelled; `store.rs`'s `unwrap_or_default` whose
  empty string the next line rejects; the empty-path and empty-goal-id wire
  sentinels the native contract defines; the map-accumulate identities; and the
  `report?.confirmationFrames ?? 0` readouts where zero confirming exposures is
  the true state before the first report.

`--fail-on-unregistered --fail-on-open` → **EXIT 0**.

**Placeholder audit** — one new high-risk marker,
`depthlock_service/store.rs:293`'s `unwrap_or_default`. It carries a `// Why:`
comment at the site (the convention the neighbouring baseline rows use) and a
baseline entry. → **EXIT 0**.

### 5. The small UI debts

- **`target_header_card.dart`** — the selection ring and hover wash animated
  through a raw `NightshadeTokens.durationNormal` instead of
  `animationDuration(context, …)`, so a user who has turned animations off
  still saw the card move. The running target's `_SpinningIcon` repeated
  regardless of the setting (a repeat cannot be shortened, so it is refused
  outright and the still glyph is drawn) and its duration is now
  `durationPulse` rather than a literal `Duration(seconds: 2)`. While there:
  the spinning glyph was hard-coded at 18 px against the still glyph's 14, so
  the target's icon grew 4 px the moment the run reached it — both now read one
  file-level constant.
- **Gutter map / minimap viewport rectangle** — both surfaces paint through
  the one `SequenceMapPainter._paintViewport`, so it is a single change: the
  fill goes from `opacityAccentTint` (12 %) to `opacityMedium` (20 %), and a
  `borderHighlight` hairline is drawn just outside the accent stroke so the
  rectangle's edge never sits primary-on-primary against the row blocks it
  covers on the 80 px strip.
- **Copy** — `'Add to List'` → `'Add to list'` (`object_info_popup.dart`,
  `object_info_tooltip.dart`, and the `lists_tab.dart` empty-state that quotes
  it) and `'Log Observation'` → `'Log observation'`
  (`observation_log_dialog.dart`'s title and its save button,
  `observation_log_settings.dart`'s empty state). The three tests and two
  comments that name those strings moved with them.

## Left open, and why

- **`NightshadeDropdown` has the same `LayoutBuilder` trap as the text field**
  (`nightshade_dropdown.dart:157`, `expand: widget.isExpanded ||
  constraints.hasBoundedWidth`). No live `AlertDialog` contains one today — the
  only file holding both, `capture_panel.dart`, keeps its dropdowns (166, 188)
  outside its dialog (423) — so it is latent, not failing. The fix is the one
  already written: wrap `_control(colors, expand: true)` in `FieldWidthBox` and
  delete the `isExpanded` parameter, which the box makes a no-op (it cannot
  make an unbounded slot fill, and a bounded one already fills). NOT done here
  because `isExpanded` is public API with nine call sites, one of them in
  `location_settings.dart` — a file the geolocation workstream is editing right
  now. Removing a public parameter mid-campaign is exactly the breakage the
  fence exists to prevent; it wants doing in one pass once both parallel
  branches have landed.

- **`packages/nightshade_core/lib/src/services/ip_geolocation.dart`** appears in
  the format commit. It is not in the geolocation workstream's stated fence
  (which names `nightshade_planetarium/.../geolocation_service.dart` and
  `services/positioning/`), and the change is formatter-only — but it is the
  one file in my diff adjacent to theirs, so it is called out here.

- **The two Windows framing goldens** — out of scope by policy, unchanged.

- **The planetarium perceptual baselines** owe a Windows re-capture (above).
  Nothing on Linux can be done about them without violating the documented
  re-baselining rule.

- **`log_export_target_test` and `integrity_check_test`**, listed as
  order-sensitive debt in `CAMPAIGN-2026-09-13.md`, both PASS in the full
  per-package runs on this commit (they appear nowhere in the base or final
  failure lists). Nothing to fix; the note is stale for this branch.

- **Four skipped tests in `nightshade_core`** are environment opt-ins (a live
  HiPS network fetch, a real sshd, two POSIX-permission cases guarded on
  Windows), not silenced failures.

