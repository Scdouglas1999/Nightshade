# w6-inspector-shift — the inspector tab switch moved the whole screen

Base `f1f739da1`, branch `agent/w6-inspector-shift`.

Owner's report (release build): clicking **Activity** or **Notes** in the
right-hand node inspector makes "the whole screen bounce to the left, revealing
nothing on the right".

## 1. Reproduced in the running app

Harness: `tools/ui_audit/drive_linux.py --profile w6shift`, `NS_AUDIT_DISPLAY=:92`,
profile seeded from `~/.cache/nightshade-ledger-preview/data`. App window
1600x900 at root (160,150) on a 1920x1200 virtual screen. Loaded
"NGC 7000 + M31 · full night" from Sequencer › Saved, selected the **Cool
camera** node, then clicked **Activity**.

### Settled state: nothing wrong

Raw 1920x1200 captures, column-profile cross-correlation over the palette +
canvas band (x 160-1440, y 400-1000), and the vertical border positions:

| landmark (root x) | Settings | Activity | Notes |
|---|---|---|---|
| nav rail / palette border | 379/380 | 379/380 | 379/380 |
| palette right edge (card) | 633/634 | 633/634 | 633/634 |
| inspector left border | 1470 | 1470 | 1470 |
| window right edge | 1760 | 1760 | 1760 |
| inspector width | 290 | 290 | 290 |
| measured shift of palette+tree | — | **+0 px** (corr 1.0000) | **+0 px** |

So the inspector's WIDTH is not the bug: it is 290px on every tab, and a
screenshot taken a few seconds after the click shows no displacement. A
settled-state check would have declared this fixed.

### The transient: a 29 px bounce

Recorded the window with `ffmpeg -f x11grab` at 25 fps while clicking
**Activity**, then measured each frame's horizontal shift against the
pre-click frame (`/tmp/ns-audit/frames`, softpipe renders ~5 real fps so
frames repeat):

```
frame 45 (1800 ms)  shift  +0     baseline
frame 49 (1960 ms)  shift  +0     whole body dims by 4/255
frame 54 (2160 ms)  shift +29 px  <-- content jumps LEFT
frame 59 (2360 ms)  shift +10 px
frame 64 (2560 ms)  shift  +1 px
frame 72 (2880 ms)  shift  +0 px  settled back
```

The entire screen body (nav rail excluded — it is outside the moving subtree)
slides 29 px left and springs back over ~400 ms. That is the owner's bounce.

## 2. Root cause

`AdaptiveTabBar` keeps its selected tab on screen from `didUpdateWidget`:

```dart
Scrollable.ensureVisible(keyContext, alignment: 0.5, ...);   // before
```

`Scrollable.ensureVisible` is not scoped to one scrollable. It walks **every
ancestor `Scrollable`** (`while (scrollable != null) { ... scrollable =
Scrollable.maybeOf(scrollable.context); }`) and scrolls each one so the target
is visible in it.

The sequencer's body is an `AnimatedTabBarView` → `TabBarView`
(`sequencer_screen.dart:539`), i.e. a horizontally scrolling pager holding
Builder / Templates / Saved / History. The inspector's Settings/Activity/Notes
strip is a descendant of that pager. So "keep this 60 px tab visible" asked the
PAGER to centre the tab too: it scrolled toward page 1, and `TabBarView`'s page
physics then snapped it back to page 0 — a bounce. `NeverScrollableScrollPhysics`
did not prevent it: that only refuses USER drags (`shouldAcceptUserOffset`),
never a programmatic `animateTo`.

"Revealing nothing on the right" is literal: page 1 (Templates) is behind
`_LazyTab`, which renders `SizedBox.shrink()` until first visited, so the strip
uncovered on the right is empty.

The precondition is that the strip is scrollable at all — with the real font
the three labels fit the 290 px column, but the bar's own scroll position is
still what `ensureVisible` targets, and any sub-pixel extent makes the ancestor
walk fire.

## 3. The fix

`packages/nightshade_ui/lib/src/components/adaptive_tab_bar.dart` —
`_ensureSelectedVisible` now scrolls **its own** `ScrollPosition`:

```dart
final target = keyContext.findRenderObject();
if (target == null || !target.attached) return;
_scrollController.position.ensureVisible(target, alignment: 0.5, ...);
```

`ScrollPosition.ensureVisible` resolves the nearest enclosing viewport — this
strip's — and applies the offset to this position only. The bar still keeps its
selected tab visible; no host scrollable is touched. Nothing about the panel's
width, the tab body, or the crossfade changed, because none of them was ever
the cause.

## 4. Proven after the fix

(see §6 for the post-fix live numbers and exit codes)

## 5. Not fixed here (same defect class, other owners' files)

`Scrollable.ensureVisible` is called with the same ancestor-walking semantics in
11 other places. Two of them are inside this very pager and will bounce the
screen the same way when they fire:

- `screens/sequencer/widgets/sequence_tree.dart:335,353` (follow-execution and
  the selected-row reveal)
- `screens/sequencer/widgets/sequence_minimap.dart:127`
- `screens/sequencer/widgets/sequence_step_finder.dart:54`

They are in files parallel agents are editing, so they are reported, not
touched. The tree ones are the most likely to be seen: they fire on every
auto-follow step during a run.
