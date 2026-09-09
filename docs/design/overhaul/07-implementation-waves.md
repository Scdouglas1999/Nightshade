# 07 · Implementation waves

Four waves, in order. Each wave is independently shippable, has a definition of done, and a
verification protocol that uses the RUNNING app, not a code read. An agent takes ONE wave (or one
screen inside wave 3) per branch. Never start wave N+1 in a branch that has not merged wave N.

Branch naming: `feature/observatory-w0-tokens`, `…-w1-shell`, `…-w2-components`,
`…-w3-<screen>`, `…-w4-cleanup`.

## Rules for every wave (read before touching code)

1. **Read `README.md`, `02-design-language.md`, then the section you are implementing.** Do not
   read the whole package to "get context"; the spec is the context.
2. **Match the mockup, not your taste.** Open the PNG next to your screenshot. Sizes in the spec are
   logical pixels; the mockups are rendered at 1× so pixels = logical pixels.
3. **Never invent a style.** If you need a colour, size, radius or duration that is not a token,
   stop and use the nearest token. If none fits, add the token to `design-tokens.json` FIRST, run
   `tools/check_tokens.py`, then mirror it into Dart (03 §0 map), then use it. The mockups obey
   the 4 px grid; the two derived exceptions are documented where they occur (rail item padding
   11 = (40 − 18) / 2; checklist row padding 14). Where a mockup pixel and a token disagree by
   ≤ 2 px, the TOKEN wins and the ±2 px rule in "matches the mockup" absorbs the difference.
4. **No new raw literals.** `BorderRadius.circular(<number>)`, `TextStyle(fontSize: <number>)`,
   `Color(0x…)`, `EdgeInsets.all(<odd number>)`, `Icons.*` are all forbidden in files you touch.
   `tools/production/ui_consistency_audit.dart` and `design_tokens_audit.dart` must report zero
   NEW findings for your files.
5. **Do not change behaviour.** Providers, routes, controllers, the DB, the API: untouched. If a
   widget's constructor changes, update its callers; if a widget is deleted, its callers use the
   replacement named in 05/06.
6. **Do not touch mobile-only code** (`apps/mobile/lib/screens/`) except through the shared shell.
7. **Verify in the running app** with the harness (below) before claiming done. A green
   `flutter analyze` is not verification. Screenshots go in `reports/observatory/<wave>/`.
8. **Run the gates**: `melos run test` for the packages you touched, `flutter analyze`, the two
   audit tools, `packages/nightshade_ui/test/design_system_gallery_test.dart` (regenerate the
   gallery goldens on Linux for `nightshade_ui` only), and the contrast tests.
9. **Commit per screen, not per wave.** Small diffs; no Co-Authored-By trailers (repo rule).
10. **When the spec and the code disagree about a FACT** (a provider name, a file that moved),
    trust the code and note the correction in `reports/observatory/<wave>/notes.md`. When they
    disagree about a DESIGN decision, the spec wins.

## Verification protocol (every wave)

```bash
# 1. Build what you will test (Rust first if native changed; it should not in this campaign)
cd apps/desktop && flutter build linux --release
# 2. Drive the app on a private display against a scratch profile
python3 tools/ui_audit/drive_linux.py start --fresh
python3 tools/ui_audit/drive_linux.py tree                 # names, roles, states — text, cheap
python3 tools/ui_audit/drive_linux.py shot reports/observatory/w1/dashboard.png
python3 tools/ui_audit/drive_linux.py click-img <shot> X Y # coordinates measured IN the shot
python3 tools/ui_audit/drive_linux.py stop
```

- Set up the same scratch state the mockups assume: skip onboarding, enter the Boston site in
  Settings › Location (42.36 / −71.06 / 40), connect Simulated Camera + Mount + Focuser from
  Equipment › discovery, load the "Mono LRGB M51" starter from Sequencer › Templates. That state
  is what `tonight.png`, `imaging.png`, `sequencer.png`, `equipment.png` show.
- Read `tree` for structure and state; read a screenshot only for layout. Budget ≤ 40 image reads.
- Compare against the mockup PNG at the same window size (1600 × 900; the harness crops and
  downscales to 1280 wide, so compare proportions, not pixels).
- Two traps from memory: the harness prefers the RELEASE bundle (build release), and a stale
  bundle reproduces the old behaviour exactly (check the bundle mtime before concluding a change
  "did not work").

## Wave 0 — Tokens (1 agent, ~1 day)

Scope: 03-tokens.md §1, §2, §3.1–3.2, §4, §5 in `packages/nightshade_ui`, plus the mechanical
literal migration in `packages/nightshade_app`. NOT §3.3 (component sizes → wave 2) and NOT §3.4
(shell metrics → wave 1): those change layout and this wave must not.

Steps:
1. `nightshade_colors.dart`: add the seven new fields (03 §1.5); new palette values; deprecate
   `surfaceAlt`; add `AppearanceAccents` per-theme swatch lists (03 §1.4).
2. `nightshade_typography.dart`: add the twelve new styles (03 §2); deprecate `h1..h6`,
   `statValue`, `statLabel`; leave `textTheme()` mappings alone.
3. `nightshade_tokens.dart`: radius values (03 §3.2), durations and curves (03 §4), opacity tokens
   (03 §5.1), `iconButtonSize*` constants. NOT button/input heights, NOT sidebar widths.
4. (moved to wave 1) — do not touch `shell_chrome_metrics.dart` in this wave.
5. `nightshade_decorations.dart`: the factory set in 03 §5.2; the existing factories become thin
   deprecated wrappers per the table at the end of 03 §5.2.
6. Contrast tests: `light_contrast_test.dart` and `red_night_contrast_test.dart` exist in
   `packages/nightshade_ui/test/`; extend both to cover `well`, and add `dark_contrast_test.dart`
   with the same floors as `check_tokens.py`.
7. Mechanical migration in `packages/nightshade_app/lib`: the 110 `BorderRadius.circular(<n>)`
   and 29 `Radius.circular(<n>)` literals → tokens per 03 §3.2 (a sed-style script is fine; commit
   it under `tools/production/`), every `Color(0x…)` that equals an OLD palette value → the
   semantic token it was standing in for. Do NOT touch the 979 `radiusInline*` sites (wave 4).
8. Add a `deprecated_text_style` rule to `ui_consistency_audit.dart` (flags `h1..h6`, `statValue`,
   `statLabel`, `surfaceAlt`, the old decoration names) and extend `design_tokens_audit.dart` to
   flag `.copyWith(fontSize:` as well as `TextStyle(fontSize:`.
9. `test/design_tokens_sync_test.dart` (03 §1.5 step 4) so the JSON and the Dart cannot drift.

Done when:
- [ ] `check_tokens.py` passes and its numbers match the comments in the Dart palettes.
- [ ] `grep -rcE "(BorderRadius|Radius)\.circular\([0-9]" packages/nightshade_app/lib | awk -F: '{s+=$2} END {print s}'` prints 0 (from 110 + 29).
- [ ] `design_tokens_sync_test.dart` passes.
- [ ] `Color(0x` in `packages/nightshade_app/lib` ≤ 40 (from 120; the rest are chart /
      image-data colours, list them in notes.md).
- [ ] App runs; screenshots of Dashboard, Imaging, Sequencer, Settings in all three themes show
      the new palette (darker canvas, brighter accent) and radii with NO layout change (chrome
      heights, button heights and rail width are identical to the audit screenshots; this is
      why §3.3 and §3.4 are excluded from this wave).
- [ ] `melos run test` green for `nightshade_ui` and `nightshade_app`.

## Wave 1 — Shell (1 agent, ~2 days)

Scope: 04-shell.md. Files listed in its table.

Steps (in this order, verifying after each):
0. `shell_chrome_metrics.dart` + `nightshade_tokens.dart` sidebar widths: the values in 03 §3.4
   (title bar 44, status bar 32, rail 64, bottom nav 64, delete `statusBarHeightCompact`, fix
   `contentStackBottomChromeHeight`).
1. `shell_navigation.dart`: grouped destinations, Darkroom added, labels renamed, descriptions
   removed (04 §3.2 names the exact types and the alias table). Add the three `navGroup*` strings and `navTonight`, `navPlan`, `navDarkroom` to
   `translations.dart` for every language present (copy the English string where a translation
   is missing and mark it `// TODO(l10n)`).
2. `side_navigation.dart` + `nav_item.dart`: rail geometry (04 §3.1); the tooltip fix goes in
   `nightshade_ui/.../nightshade_tooltip.dart` (04 §3.1 says exactly where and adds a test).
3. `title_bar.dart`: top bar (04 §2) with the command field placeholder (the palette itself is
   step 6; the field can open a stub dialog until then). Remove the profile button. Add the help
   popover (05 §11) and DELETE `widgets/contextual_tour_prompt.dart` and its 13 call sites in the
   same commit (the tours themselves stay reachable from the popover).
4. `status_bar.dart`: instrument bar (04 §5). Remove the web-dashboard/share buttons; put the share
   action in the remote indicator's menu in the top bar.
5. `app_shell.dart`: the grid (04 §1); delete `DashboardCommandBar` usage from
   `dashboard_screen.dart` (the dashboard will temporarily show its old content minus the bar;
   that is expected until wave 3).
6. Command palette (04 §7) with Screens + Settings + Actions groups (Targets group is wave 3 Plan).
7. `nightshade_bottom_navigation.dart` + `shell_navigation.dart` bottom lists: five slots + More
   sheet (04 §3.3 lists every member that changes).
8. `PageHeader` widget in `nightshade_ui` (04 §4) — created here, adopted per screen in wave 3.
   `ScreenHeader` keeps working (deprecated).

Done when: every box in 04 §8 is ticked with screenshot evidence in `reports/observatory/w1/`.

## Wave 2 — Components (1–2 agents, ~3 days)

Scope: 05-components.md plus 03 §3.3 (button and input heights, applied here because
`NightshadeButton`/fields are rebuilt here). Only `packages/nightshade_ui` plus the gallery and
goldens, plus compile fixes in `nightshade_app` for renamed parameters.

Build in this order (each is used by the next): Panel + PanelHead → Readout family → Chip /
InstrumentPill / StatusDot changes → Buttons + NightshadeIconButton → Fields + FormRow → Tabs
(underline) + SegmentedControl → NightshadeToolbar → NightshadeBanner + EmptyState + Dialog →
Glass → SidePanel + SectionTitle → ListRow / DeviceRow / Candidate → Checklist → NightBand.

Two agents may split at "Glass →": agent A does everything before it, agent B does Glass,
SidePanel, list rows, Checklist, NightBand (they depend only on Panel/Readout, which A finishes
first; B waits for A's first commit).

Done when:
- [ ] Every component in 05 exists, is exported, has a gallery section and a golden.
- [ ] `components.png` and the gallery golden match section for section (same components, same
      sizes; colour identical; fonts identical). This comparison is made by a DIFFERENT agent (or
      the owner) than the one who regenerated the golden, with both images side by side, and the
      verdict is written in `reports/observatory/w2/golden-review.md`.
- [ ] `flutter test packages/nightshade_ui` green, including new widget tests: `Readout(value:
      null)` renders "—"; `NightBand` positions the now marker at the right fraction; `Checklist`
      strikes done titles; `SidePanel` strip selection; underline indicator width equals label
      width + 4; `NightshadeTooltip` hides on rebuild while hovered; every animation honours
      `MediaQuery.disableAnimations`.
- [ ] Nothing in `nightshade_app` changed except compile fixes for renamed parameters.

## Wave 3 — Screens (one agent PER screen, parallel, ~1–2 days each)

Scope: 06-screens.md, one section per agent. Order of value: **Tonight → Imaging → Sequencer →
Equipment → Plan → Settings → Guiding → Weather → Analytics → Darkroom → Onboarding.** The first
four are the ones the owner will judge; do them first and do them exactly.

Per-screen checklist (copy into the PR description and tick):
- [ ] Uses `PageHeader`; no `ScreenHeader`, no subtitle sentence, no second header row.
- [ ] Tabs are `AdaptiveTabBar` underline style; no `SubTabButton`, no pill tabs.
- [ ] Zero `NightshadeCard` without `onTap`; containers are `NightshadePanel`; insets are `well`;
      nesting depth ≤ panel → well.
- [ ] Every number that is a measurement is a `Readout`; every `---`/`--:--` is gone.
- [ ] Every `IconButton` in this screen's files is a `NightshadeIconButton` with a tooltip (this
      is where the 178-site migration happens, screen by screen).
- [ ] Every raw `TextStyle(` in the screen's files replaced by a named style (count before/after
      in the PR).
- [ ] The screen's tour prompt is removed; the help popover lists the tour.
- [ ] The screen's setup nags are reduced to at most one `Banner`, and the same problem is
      represented in the Tonight checklist (verify by making the problem exist and counting).
- [ ] Empty, loading and error states each use the single pattern.
- [ ] Screenshot at 1600 × 900 beside the mockup; screenshot at 700 × 900; screenshot in light and
      red night. All four in `reports/observatory/w3-<screen>/`.
- [ ] `tree` output saved; every interactive control has a name.
- [ ] Screen tests green; goldens for this screen NOT regenerated on Linux (they are Windows
      goldens; mark as expected failures in the PR and list them).

Definition of "matches the mockup": same elements in the same positions and the same reading
order; sizes within ±2 px of the spec; colours identical (token); fonts identical. Content values
will differ (simulator data); that is fine. Screens WITHOUT a mockup (Guiding, Weather,
Analytics, Darkroom, Onboarding) are judged against their 06 text plus `components.png`: every
element must be one of the sheet's components, laid out per 06.

## Wave 4 — Cleanup (1 agent, ~1 day)

- Sed-replace the 979 `NightshadeTokens.radiusInline*` sites per 03 §3.2 (one commit), then
  delete the constants.
- Delete deprecated members: `surfaceAlt`, `h1..h6`, `statValue`, `statLabel`, `ScreenHeader`,
  `SubTabButton`, `CardVariant`, `ButtonVariant.outline`, `StatusPill`, the old
  `NightshadeDecorations` wrappers, `elevationLevel*`/`shadow*`, the deprecated opacity tokens,
  the extra named curves, `nav*Desc` strings (the tour prompts and `DashboardCommandBar` were
  already deleted in waves 1 and 3).
- Run both audit tools with the scoped-out allowlist emptied of anything the overhaul fixed.
- Update `docs/architecture/ui-theming.md` to point at this folder as the design contract; move
  `docs/design/token-migration-map.md` and `icon-migration-map.md` under `docs/design/overhaul/
  archive/`.
- Regenerate the three gallery goldens; open the Windows golden regeneration as a follow-up for
  the owner's rig (cannot be done on Linux).
- Final full-app screenshot set in all three themes at 1600 × 900 and 700 × 900 into
  `reports/observatory/final/`, and update `01-audit.md` with a "Resolved" column.

## What NOT to do (the failure modes we have seen from agents)

- Do not "improve" a mockup. If it looks wrong to you, implement it and write the objection in
  notes.md; the owner decides.
- Do not add a border because something "looks unfinished". Tone does the work; check the
  surface tokens before adding lines.
- Do not add a subtitle, a hint sentence, a tooltip paragraph, or a "Learn more" link to explain
  a screen. The help popover exists for that.
- Do not add a toast, banner or dialog for a setup problem. Route it to the checklist.
- Do not scale fonts down to make something fit. Reduce content or let it scroll.
- Do not regenerate Windows goldens on Linux and commit them.
- Do not touch `packages/nightshade_core`, `nightshade_bridge`, `native/`, or `server/`.
- Do not start a second screen in the same branch as the first.
