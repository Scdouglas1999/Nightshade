# 01 · Audit of the shipped UI (7.0.0, 2026-09-09)

Everything below was observed in the RUNNING desktop app (release bundle of 7.0.0, driven with
`tools/ui_audit/drive_linux.py` on a 1600×900 window, fresh profile, simulated camera/mount/focuser,
Boston observing site). Screenshots are in `audit/`. Each finding names the screenshot that shows it.

This is the "why" behind every decision in 02–06. Implementing agents: read it once so you
understand what a change is fixing, then work from 03–07.

## What is already good (keep, do not "improve")

- **Palette discipline.** Every text/status colour clears WCAG AA on every surface, in all three
  themes, and the reasoning is documented in `nightshade_colors.dart`. Red night is a real
  wavelength constraint (G == B on every colour), not a tint. The overhaul keeps this and adds a
  checker (`tools/check_tokens.py`).
- **Type choices.** Hanken Grotesk + Spline Sans Mono, bundled offline. Right fonts, wrong scale.
- **Icons.** Lucide everywhere (3,189 uses vs 34 stray Material icons). Keep Lucide.
- **The planetarium** (`audit/23_planetarium.png`) is the one screen that already feels premium:
  edge-to-edge canvas, floating time control, compass, quiet labels. It is the model for Imaging.
- **Buttons and cards are already migrated** (`NightshadeButton` 847 uses, `NightshadeCard` 291;
  raw `ElevatedButton`/`OutlinedButton` at 0). The remaining debt is shape and type literals:
  110 raw `BorderRadius.circular(n)` + 29 `Radius.circular(n)` (979 more already go through the
  value-named `radiusInline*` tokens that a later pass must fold onto the semantic scale),
  2,420 raw `TextStyle(`, 120 `Color(0x…)`, 178 raw `IconButton(` in `nightshade_app/lib`.
- **Sequencer templates page** (`audit/30_seq_templates.png`) is close: clear cards, good copy.
- **Bottom status bar** as an idea (instrument apps have one). Its content is the problem.

## Findings

Severity: **S1** = makes the app look amateur or confuses navigation; **S2** = visible polish debt;
**S3** = defect found along the way.

### A. Chrome: too much of it, and it repeats itself (S1)

| # | Finding | Evidence |
|---|---|---|
| A1 | Three status surfaces show the same facts. Clock + LST appear in the Dashboard command bar AND the bottom bar. "Idle" appears three times on the Dashboard (command bar, bottom-left, bottom-middle). | `audit/19_dashboard_connected.png` |
| A2 | The Dashboard command bar (Idle / No Target / Temp / Focus / HFR / RMS / clock / Local / Edit Dashboard) exists ONLY on the Dashboard, so global status vanishes on every other screen. It is a screen header pretending to be shell chrome. | `audit/03_dashboard.png` vs `audit/10_equipment.png` |
| A3 | Sequencer stacks three header layers before content: tab bar (48 px) + "Sequence Builder / Assemble the instructions tonight's run executes." title block (70 px) + 20-icon toolbar (48 px). Content starts 166 px down, 23% of a 720 px viewport. The title repeats the selected tab. | `audit/10_sequencer.png` |
| A4 | Imaging stacks an info banner (40 px) + viewer toolbar + capture bar + status bar. The image, which is the point of the screen, gets ~65% of the height. | `audit/21b_imaging_image.png` |
| A5 | Narrow window (< 768 px) stacks the status bar ON TOP of the bottom nav: 110 px of bottom chrome on a 900 px window. | `audit/42_narrow_imaging.png` |
| A6 | Title bar wastes its centre; the wordmark, four icon buttons and window controls are all it holds. | every screenshot |

### B. Surfaces: everything is a bordered box, so nothing has hierarchy (S1)

| # | Finding | Evidence |
|---|---|---|
| B1 | Boxes inside boxes inside boxes. Dashboard Guiding card → bordered chart well → bordered "No guide data" inset. Frame card → bordered "Waiting for first frame" bar → bordered empty area. Three 1 px borders of the same colour at three depths. | `audit/19_dashboard_connected.png` |
| B2 | Every panel, card, chip, tab, field and toolbar button uses the same 1 px `border` (#2E353F). The eye cannot tell a container from a control. | all |
| B3 | Equipment device cards have a full green border (status), an amber inset warning box, a stat row AND a button row. Four competing emphases per card; the same amber "session only" paragraph is repeated on all three cards. | `audit/18_equipment_connected.png` |
| B4 | Cards with `Card`-style padding around a single line of text ("No runs yet — your first night will appear here.") | `audit/03_dashboard.png` |

### C. Type: one size, one weight (S1)

| # | Finding | Evidence |
|---|---|---|
| C1 | Almost all UI text is 12–13 px regular. Section headings are 11 px uppercase muted. Only page titles are large. Instrument readouts (temperature, RA/Dec, HFR, focus position) render at 12–13 px mono, the same weight as their labels. The most important numbers on screen are the quietest thing on it. | `audit/19_dashboard_connected.png` right column |
| C2 | Page subtitles are filler sentences: "Assemble the instructions tonight's run executes.", "Live cloud tracking and safety monitoring", "Customize how Nightshade looks". They cost 20–28 px of height each and say nothing the title didn't. | `audit/10_sequencer.png`, `audit/10_weather.png`, `audit/12_appearance.png` |
| C3 | Sidebar items are two lines (title + subtitle). The subtitles ("Automation", "Session stats", "Cloud radar") are placeholders, and the two-line rows make the rail read as a settings list rather than navigation. | `audit/03_dashboard.png` |

### D. Navigation: eight peers, hidden features, five tab styles (S1)

| # | Finding | Evidence |
|---|---|---|
| D1 | Eight flat sidebar peers with no grouping. Settings is hidden in the title bar. Darkroom, Session review, Polar alignment, Flat wizard, Live stacking, Mosaic, Catalogs have NO navigation home; they are reached from buttons inside other screens or not at all (`app_router.dart` map in 04-shell.md). | `audit/03_dashboard.png`; router |
| D2 | Five different tab-bar styles: Sequencer pill-in-bar, Plan Tonight outlined pill, Projects/Discover segmented control, Imaging 4×2 tile grid, Settings tree. Plan Tonight has 6 tabs, one of which (Discover) has 3 sub-tabs. Analytics has 6. | `audit/10_sequencer.png`, `audit/22_plan_reco.png`, `audit/26_projects.png`, `audit/10_imaging.png` |
| D3 | Imaging's side panel uses a 4×2 grid of tile-tabs; the eighth label truncates to "Annotatio…". | `audit/10_imaging.png` |
| D4 | The Dashboard is two completely different layouts depending on whether equipment is connected ("briefing" with Moon/Targets/Readiness cards vs "cockpit" with frame/guiding/equipment). Same nav item, different information architecture. | `audit/03_dashboard.png` vs `audit/19_dashboard_connected.png` |
| D5 | Sequencer toolbar: 20 unlabeled icon buttons in a row. | `audit/31_seq_loaded.png` |
| D6 | "Plan Tonight" and Dashboard "Tonight's briefing" compete for the word Tonight. | `audit/03_dashboard.png` |

### E. Noise: nags, tours and placeholders (S1)

| # | Finding | Evidence |
|---|---|---|
| E1 | Every section fires its own "X Tour" toast in the bottom-right corner on first visit: Dashboard, Imaging, Sequencer, Guiding, Weather, Analytics, Settings, Equipment, Planetarium, Framing. Ten toasts, same spot, covering content (the Session panel in Imaging, Calibration in Guiding). | `audit/10_guiding.png`, `audit/21b_imaging_image.png`, `audit/24_framing.png` |
| E2 | One missing catalog produces FOUR nags: Catalog Setup dialog at launch, info banner across Imaging, an in-image warning box, and a modal ("Annotation Catalogs Required") on the first snapshot. Plus a card on Plan. | `audit/02_after_skip.png`, `audit/21_imaging_snapshot.png` |
| E3 | Two competing prompts at first launch: the Catalog Setup dialog AND the Dashboard Tour toast, simultaneously. | `audit/02_after_skip.png` |
| E4 | `---` / `--:--` placeholders for every unavailable value (Temp, Focus, HFR, RMS, Moonrise, LST). Eleven dashes on the idle Dashboard. | `audit/03_dashboard.png` |
| E5 | An emoji (🔭) as the equipment-profile icon, in a Lucide-icon app. | `audit/15_equipment_manual.png` |

### F. Layout defects (S3, fix during the overhaul)

| # | Finding | Evidence |
|---|---|---|
| F1 | Equipment content pane stops ~115 px short of the window bottom (black void under the discovery list). | `audit/15_equipment_manual.png` |
| F2 | The Discovery panel OVERLAYS the device cards (Focuser card is cut at its button row). | `audit/17b.png`, `audit/18_equipment_connected.png` |
| F3 | Sequence name truncates in its own header ("Mono LRGB M51 (…") while 40% of the bar is empty. | `audit/31_seq_loaded.png` |
| F4 | Collapsed-rail hover tooltip ("Dashboard / Overview & status") stays painted after the pointer leaves. | `audit/40_red_dashboard.png` |
| F5 | Onboarding uses ~30% of a 1600×900 canvas; the rest is an empty bordered card. | `audit/01_first.png` |
| F6 | Light theme "Start" button: light green fill on a green-tinted bar, low contrast. | `audit/34_light_dashboard.png` |

### G. Colour (S2)

| # | Finding |
|---|---|
| G1 | The accent (#5B9EC4) is desaturated enough that selection, primary buttons and info text all read as "greyish blue". Nothing on screen is allowed to be confident. |
| G2 | Status green is used as a whole-card border (Equipment), which is louder than the status itself. |
| G3 | Light theme is competent but flat: white cards with grey borders on grey. Same border-everywhere problem as dark. |
| G4 | textSecondary (#9AA3AD) and textMuted (#9099A6) are nearly identical, so the three-level text ladder collapses to two. |

## What the overhaul changes, in one paragraph

One persistent status surface (the bottom instrument bar) instead of three. A 44 px top bar with a
global search/command field. A 64 px icon rail grouped by night phase (Observe / Prepare / Review)
with Darkroom promoted to a destination and Settings reachable from the rail. One page-header
pattern (title + underline tabs + actions on a single 56 px row; no subtitle sentences). Surfaces
separated by tone, not borders, with a maximum nesting depth of panel → well. A type scale with
loud mono readouts and quiet labels. One accent that is actually an accent. One tab style. One
banner style, one instance per problem. A first-run checklist on Tonight that replaces every nag
and tour toast. Same routes, same providers, same data: this is a presentation-layer overhaul.
