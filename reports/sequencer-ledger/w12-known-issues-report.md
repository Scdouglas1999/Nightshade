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

