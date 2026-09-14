# W16 — Equipment › Profiles: menu anchor + empty pane

Workstream `w16-profiles`, branch `agent/w16-profiles`, base `5b2235cc7`.

## 0. The screen the owner meant is NOT the one the brief pointed at

The brief orients on `packages/nightshade_app/lib/screens/settings/equipment_profiles_screen.dart`
(Settings › Equipment profiles). The owner's words were "Profiles **in Equipment**" and "the
profiles **sub tab**". Live, that is the **Equipment screen's `Profiles` tab** —
`packages/nightshade_app/lib/screens/equipment/equipment_screen.dart` (`PageHeader` tabs
`Devices | Profiles 2 | Optical train`, `equipmentTabIndexProvider`). Settings ›
Equipment profiles has no tabs and no three-dot menu on a profile row.

Both defects reproduce on the Equipment tab and neither reproduces on the Settings screen, so the
Settings screen was left alone. Evidence: `shots/08-BEFORE-profiles-tab.png` (the tab, with the
`Profiles 2` tab strip and the `+` in the list header).

## 1. Live reproduction setup

Release bundle built from this worktree; the Rust bridge is required or the app aborts at startup
(`libnightshade_bridge.so could not be loaded, or it is stale`). `native/nightshade_native/target`
is a git symlink to a shared cargo dir that this worktree materialised as a plain FILE, so cargo
could not create `target/release`; built with `CARGO_TARGET_DIR=/home/scdouglas/.cache/ns-worktrees/cargo-target`
instead of modifying the tracked entry.

    flutter build linux --release                  # EXIT=0
    cargo build --release --package nightshade_bridge   # EXIT=0 (CARGO_TARGET_DIR set)
    cp .../libnightshade_bridge.so apps/desktop/build/linux/x64/release/bundle/lib/

Harness: `NS_AUDIT_DISPLAY=:91 NS_AUDIT_RUNTIME=/tmp/ns-audit-w16 LIBGL_ALWAYS_SOFTWARE=1`,
`drive_linux.py start --profile w16`, `resize 1920 1080` (the owner's laptop size).
AT-SPI was unavailable in this session (`Could not activate remote peer org.a11y.atspi.Registry`),
so everything was driven by `shot` + `click-img`/`click-xy`.

Two profiles seeded directly into the scratch SQLite (`equipment_profiles`) because with zero
profiles the app routes to `/onboarding` instead of the shell:
`Redcat 51 + 2600MC` (active + default, 250/51 mm, 4 filters, 5 devices) and
`Esprit 100 + 2600MM` (550/100 mm, 3 filters, 4 devices).

All shots under `/tmp/ns-audit-w16/shots/`.

## 2. Defect 2 (blank negative space) — cause PROVEN, and it is none of the brief's three

The brief offered three candidates *for the Settings screen*: selection not taking effect, the
mobile branch being taken, or sections leaving a wide pane empty. **None applies.** On the real
screen the cause is that the Profiles tab has **no detail pane at all**.

`equipment_screen.dart` `_ProfilesTab.build` (before):

    return Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _profilesColumnWidth,      // const double = 360.0
        child: ProfileSidebar(...),
      ),
    );

The tab body is a single 360 px column pinned top-left. Measured live at 1920x1080 with the nav
rail expanded (`shots/08-BEFORE-profiles-tab.png`): the list ends at image x=386 of 1280
(= 579 real px) and everything right of it is bare `colors.background` — **~1340 of 1920 px,
70% of the content area, empty**. Selection works fine (the footer's `Connect all` / `Edit profile`
track the selected card); there is simply nothing built to fill the space. Exactly the owner's
"most of the screen is blank negative space that doesn't fill with anything".

## 3. Defect 1 (menu lands mid-screen) — cause PROVEN

`profile_sidebar.dart:312 _showProfileContextMenu` (before):

    final overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromLTWH(offset.dx, offset.dy, 0, 0),     // offset is a GLOBAL coordinate
      Offset.zero & overlay.size,
    );

`offset` arrives global (from `box.localToGlobal(...)` at `:684` and `details.globalPosition` at
`:609`/`:612`), but `showMenu`'s `position` insets are measured in the **Navigator's overlay**
coordinate space. There is no conversion, so the menu is placed at
`overlayOrigin + globalAnchor` — double-counting the overlay's own origin.

The overlay origin is non-zero because of the nested Navigator: `app_router.dart:75` is a go_router
`ShellRoute`, and `app_shell.dart` puts its child inside the chrome —
`Scaffold > Column[ TitleBar, Expanded > Row[ SideNavigation, Expanded > ... > child ] , StatusBar ]`.
So the overlay's global origin is `(SideNavigation width, TitleBar height)`.

### The live experiment that proves it (and refutes the alternatives)

The `SideNavigation` width is the only term I can vary without touching anything else. Same card,
same button, two rail widths:

| | rail right edge | card right edge | menu left edge | menu − card |
|---|---|---|---|---|
| rail expanded (`shots/11-menu-try2b.png`) | 146 | 379 | **533** | 154 |
| rail collapsed (`shots/15-menu-narrowrail2.png`) | 42 | 275 | **325** | 50 |
| delta | −104 | −104 | **−208** | −104 |

(image px, 1280-wide capture of a 1920 window; x1.5 for real px)

The card moved left by exactly the rail delta (−104), as any widget in the content column must.
**The menu moved by exactly twice that (−208).** That is the arithmetic signature of
`overlayOrigin + globalAnchor`: both terms contain the rail width, so the menu moves twice when the
rail moves once.

This refutes the two alternatives outright:
* a **fixed offset / wrong anchor widget** would have moved the menu by −104, same as the card
  (predicted x=429, measured 325 — off by 104 px);
* an intervening **`Transform`/`FittedBox`** would scale the anchor, not translate it by a term
  that tracks the nav rail, and would not produce a clean 2x.

The residual `menu − card` column is the overlay origin itself: 154 image px = 231 real with the
rail at 219 real, and 50 image px = 75 real with the rail at 63 real — the overlay origin tracks
the rail width 1:1, ~12 real px of it being the content column's border/padding. Vertically the menu
sat 39 image px (58 real) below the card bottom at both rail widths, against a 42 real px `TitleBar`
— i.e. the y term is the TitleBar height and does not move with the rail. Both axes behave exactly
as `overlayOrigin + globalAnchor` predicts.

So: the brief's **candidate (1), the nested `ShellRoute` Navigator, is the cause** — with one
refinement that matters for the fix. It is *not* that `localToGlobal(ancestor: overlay)` returns
garbage (the overlay *is* a proper ancestor here); it is that this call site never converts to
overlay space at all. The conversion is missing, not broken.

### Second, smaller anchor defect at the same call site

`profile_sidebar.dart:684` computes the origin from `context.findRenderObject()`, where `context`
is the **card's** build context, not the button's — so even in the right coordinate space the menu
would anchor on the card's bottom-right corner rather than on the three-dot button at the card's
top-right. Fixed together with the space conversion.

## 4. Blast radius of the menu-anchor cause

`showMenu` is called from 11 places. Flutter's own `PopupMenuButton` and `DropdownButton` do the
overlay conversion internally, so only the HAND-ROLLED `showMenu` call sites can carry this bug.
Audited every one:

**Correct — converts with `localToGlobal(..., ancestor: overlay)`:**
* `equipment_screen/layout_rail.dart:319` (the status rail's profile menu)
* `equipment/widgets/connected_device_card/actions_and_telemetry.dart:818`
* `equipment/widgets/discovery_panel/device_row_item.dart:423`
* `shell/widgets/shell_help_popover.dart:63`
* `analytics/widgets/image_thumbnail_strip_parts/_thumbnail.dart:510` (`_menuPosition`)

**Same defect — a GLOBAL coordinate used as if it were overlay-local, all under the ShellRoute:**
* `equipment/widgets/profile_sidebar.dart:327` — the owner's report. **FIXED here.**
* `planetarium/planetarium_screen/sheets.dart:105` — `_showContextMenu(context, position)` builds
  `RelativeRect.fromLTRB(position.dx, position.dy, overlay.size.width - position.dx, ...)` from a
  global pointer position. `/planetarium` is a ShellRoute route, so its right-click menu is
  displaced by the same `(rail width, title-bar height)`.
* `sequencer/widgets/sequence_tree_context_menu.dart:102` and `:367` — both build
  `Rect.fromLTWH(position.dx, position.dy, 1, 1)` from a global pointer position; the comment at
  `:99` even says "RelativeRect from the global pointer position so the menu opens exactly under
  the cursor", which is precisely what it does not do under this shell. Two menus: the node menu
  and the fold menu.

**Latent, not currently visible:**
* `widgets/transient_alert_badge.dart:100` — uses `renderBox.localToGlobal(Offset.zero)` with no
  `ancestor:`. It is mounted in `shell/widgets/title_bar.dart:284`, i.e. OUTSIDE the nested
  navigator, so `Overlay.of(context)` there resolves to the ROOT overlay at (0,0) and global ==
  overlay-local. It renders correctly today and breaks the moment the badge moves under the shell
  child. Left alone: changing it is a title-bar change with no live defect behind it.

**Explicitly checked and NOT affected (the brief asked):**
* `NightshadeDropdown` (`nightshade_ui/lib/src/components/nightshade_dropdown.dart:112`) —
  `field.localToGlobal(Offset.zero, ancestor: overlay) & field.size`. Correct.
* `PopupMenuButton` under Settings — `settings/equipment_profiles_screen_parts/profile_details_rendering.dart:85`
  (the Settings profile pane's three-dot), `settings/pairing_screen.dart:419`, and
  `nightshade_ui/.../phd2/guide_graph_advanced.dart:310`. Flutter's implementation converts with
  `ancestor: overlay`, and the overlay IS an ancestor of the button under this shell, so these are
  correct. **Verified live**, not just read: `shots/20-settings-menu2.png` shows the Settings
  profile menu opening on its button (button at image (1245,105), menu spanning x 1186-1258,
  y 96-238), correctly clamped to the right window edge.

So the nested `ShellRoute` navigator is the shared cause, but it only bites where a call site
forgets the conversion. **Four menus besides this one are still wrong** (planetarium context menu,
sequencer node menu, sequencer fold menu — the latter two in one file). They are outside this
workstream's files and belong to other screens; the reviewer should route them.

## 5. What changed

`packages/nightshade_app/lib/screens/equipment/widgets/profile_sidebar.dart`
* `_showProfileContextMenu` takes a `Rect globalAnchor` and converts it with
  `overlay.globalToLocal(...)` before building the `RelativeRect`. Fixed at the cause: the
  conversion works for any overlay origin and for an intervening transform, rather than subtracting
  a measured constant.
* The overflow button is wrapped in a `Builder` so the anchor is the BUTTON's render object and the
  menu hangs off the control that opened it, not off a corner of the card.
* The null-fallback in the old anchor maths is gone. A just-pressed button is laid out; a fallback
  offset there is how a menu ships in the wrong place instead of failing.
* Right-click / long-press pass `details.globalPosition & Size.zero` — a point, in the same space.

`packages/nightshade_app/lib/screens/equipment/dialogs/profile_editor_dialog.dart`
* New `ProfileEditorMode.profilePage`: the whole editor as a page, no dialog chrome, no
  `Navigator.pop` (`_closeAfterSave` already handled `mode != full`), footer = Save alone
  (`_footerActions` already gated Cancel on `full`). Form column capped at
  `profilePageMaxWidth = 1200`, left-aligned.
* Reuses the existing, tested editor rather than a new read-only inspector, so create/import/
  export/duplicate/delete/set-active/set-default/edit/save and the validation and error paths are
  untouched.

`packages/nightshade_app/lib/screens/equipment/equipment_screen.dart`
* `_ProfilesTab` is now a `ConsumerWidget` with a `LayoutBuilder`: 360 px list + `Expanded`
  inspector above `_profilesTwoPaneMinWidth` (360 + 520), single column below it and when there are
  no profiles.
* `_ProfileInspector` holds the editor keyed on profile id, inside an `AnimatedSwitcher` at
  `animationDuration(context, NightshadeTokens.durationQuick)` / `curveStandard` — a cross-fade,
  top-left aligned so the incoming form's heading does not slide, and zero-duration under
  `MediaQuery.disableAnimations` via the shared helper.
* `_NoProfileSelected` covers "profiles exist, none selected" only. With no profiles the tab is ONE
  column so the list's existing empty state does the inviting — splitting there would have put two
  "No profiles yet" empty states side by side, each offering to create one.

## 6. Tests

`test/screens/equipment/profile_sidebar_menu_anchor_test.dart` (new, 5 cases) — mounts the sidebar
inside a NESTED `Navigator` inset from the window, the way `AppShell` mounts a routed screen.
Parameterised over insets 0/64/220 plus a case asserting the button-to-menu offset does not change
with the inset, plus the right-click path.

Proof it catches the defect: with `_showProfileContextMenu` reverted to the pre-fix maths the suite
fails 4/5 and the printed numbers are the theory exactly — "it is 64.0 px off" at inset 64,
"220.0 px off" at inset 220, drift `got [0.0, 220.0]`. The inset-0 case passes on the broken code,
which is why no existing test caught this: mounted at the window origin the two are identical.

One harness trap worth recording: the route hands its child TIGHT constraints, so a bare
`SizedBox(width: 360)` was widened to the whole window, put the button at the right edge, and the
menu was clamped back on screen — which HID the misplacement in one case. The sidebar is wrapped in
`Align` for that reason. Also, the card's `onDoubleTap` recognizer holds the gesture arena 300 ms,
so `pumpAndSettle` alone never delivers the tap (`_tapMenuButton` pumps 400 ms).

`test/screens/equipment/profiles_tab_inspector_test.dart` (new, 4 cases) — the pane exists and takes
the majority of a 1920 px window with its left edge at the list's right edge; clicking the other
profile swaps the pane (asserted on the editor's id key and its `profile.name`, not on copy that
appears in both columns); no profiles gives one full-width invitation and exactly one "No profiles
yet"; below the two-pane width the tab stays a single column with no exception.

## 7. Live after-evidence (same app, same window size, same route as the before shots)

Rebuilt bundle, freshness confirmed by `strings lib/libapp.so | grep -c "Pick a profile"` = 2.

| | before | after |
|---|---|---|
| Profiles tab at 1920x1080 | `shots/08-BEFORE-profiles-tab.png` — 360 px list, ~1340 px bare background | `shots/36-AFTER-profiles-tab.png` — list + editor filling to the window edge: Profile identity, Optical train (250/51 mm, derived **f/4.9**), Devices with driver ids, Save changes |
| three-dot menu, rail expanded | `shots/09..11-menu-try2b.png` — button image (361,137), menu at (533,224) | `shots/37-AFTER-menu.png` — button (361,137), menu at (353,133): on the button |
| narrow, 1100x800 | — | `shots/38-AFTER-narrow.png` two panes, no overflow; `shots/39-AFTER-menu-narrow.png` menu on the lower card's button (button (543,320), menu (524,313)), fully on screen |
| selection | pane did not exist | `shots/40-AFTER-select-second.png` — clicking Esprit 100 swaps the pane: Sky-Watcher Esprit 100ED, 550/100 mm, **f/5.5 recomputed**, Default toggle off, footer gains "Use this profile" |

Softpipe note: the app died twice with "Timed out waiting for OpenGL frame of size 1920x1080 (have
1600x900)" while other agents' builds loaded the machine. It survives with ~25 s of settle before
and after the resize; the after-shots above are all at a confirmed `1920x1080+0+0`.

## 8. Verification commands and exit codes

    flutter build linux --release                                        EXIT=0
    cargo build --release --package nightshade_bridge                    EXIT=0
      (CARGO_TARGET_DIR=/home/scdouglas/.cache/ns-worktrees/cargo-target)
    dart format --output=none --set-exit-if-changed packages/nightshade_app   EXIT=0  (0 changed)
    dart analyze  (in packages/nightshade_app)                           EXIT=0
      873 issues: ALL `info`, 0 error, 0 warning. All pre-existing
      `deprecated_member_use` from the Flutter 3.44 / pinned-CI drift; NONE in a file I touched.
    flutter test test/screens/equipment --concurrency=4                  EXIT=0  (+173)
    flutter test test/screens/settings  --concurrency=4                  EXIT=0  (+615)

`dart analyze` needed `flutter pub get` in the package first; without a resolved
`.dart_tool/package_config.json` it reports every Flutter import as `uri_does_not_exist`
(179,435 bogus issues).

## 9. Left undone, deliberately

* **The four other mispositioned menus** (planetarium context menu, sequencer node + fold menus)
  are the same cause in files this workstream does not own. Documented in §4 for routing, not
  touched.
* **`transient_alert_badge.dart`** is latent-only (root overlay, correct today). Not touched.
* **Settings > Equipment profiles** was left completely alone: verified live that its pane fills,
  auto-selects the active profile and anchors its menu correctly (`shots/18`, `shots/20`). The
  brief's three candidate causes were all for that screen and none of them is the owner's defect.
* **On-sky / owner-hardware validation** is owed as always; this was verified on the Linux release
  bundle under Xvfb, not on the imaging laptop.
* **`native/nightshade_native/target`** is committed as a symlink but materialised in this worktree
  as a plain text file holding the shared cargo path, which breaks a bare `cargo build`. Worked
  around with `CARGO_TARGET_DIR`; the tracked entry was NOT modified, so the tree stays clean. Worth
  a look by whoever owns worktree creation.
