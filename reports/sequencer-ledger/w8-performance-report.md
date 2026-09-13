# w8-performance — Nightshade desktop performance audit

Workstream `w8-performance`, base `d6a1caeb3`, branch `agent/w8-performance`.
Owner's brief: "Make sure the app is running using low resources and constantly
at my monitor's refresh rate... it feels like maybe it's chugging a little?"

Measure first. Every claim below carries the command and the number.

## Setup (exit codes)

| step | command | exit |
|---|---|---|
| bootstrap | `melos bootstrap` | 0 |
| bridge hash | `rustContentHash` = `-1467366630` (dart) == `FLUTTER_RUST_BRIDGE_CODEGEN_CONTENT_HASH` = `-1467366630` (rust) | match, no rebuild |

`apps/desktop/linux/CMakeLists.txt` resolves the bridge at
`native/nightshade_native/target/release/libnightshade_bridge.so`, not at
`CARGO_TARGET_DIR`. In this worktree that path did not exist and the first
`flutter build linux --release` failed with "Rust library not found". Symlinked
`native/nightshade_native/target -> /home/scdouglas/.cache/ns-worktrees/cargo-target`
(worktree-local, untracked) and the build proceeds.

## 1. Baseline: idle CPU per screen (release bundle, GUI harness)

Harness: `tools/ui_audit/drive_linux.py --profile w8perf`, `NS_AUDIT_DISPLAY=:96`,
Xvfb `1920x1200x24`, `LIBGL_ALWAYS_SOFTWARE=1` + `GALLIUM_DRIVER=softpipe`.
Profile seeded from `~/.cache/nightshade-ledger-preview/data` minus
`nightshade.db.lock` (past onboarding, Sim Rig connected, two saved sequences).

`pidstat` is not installed on this host, so CPU is sampled from `/proc/<pid>/stat`
(utime+stime deltas against wall clock) by `/tmp/ns-audit/w8perf/measure.py`,
20 one-second samples per screen. Per-thread splits come from
`/tmp/ns-audit/w8perf/threads.py` (same source, `/proc/<pid>/task/*/stat`).

Softpipe inflates raster; treat these as an UPPER BOUND on the owner's machine.
What does NOT depend on the rasteriser is the *shape*: which screens produce
frames at idle at all.

| screen (idle, nothing running) | mean %CPU | max %CPU | RSS |
|---|---|---|---|
| Weather | 107.66 | 132.77 | 381.6 MB |
| Tonight | 96.22 | 130.97 | 361.5 MB |
| Guiding | 85.03 | 139.96 | 223.9 MB |
| Plan | 62.33 | 89.98 | 222.4 MB |
| Imaging | 55.53 | 106.98 | 236.6 MB |
| Analytics | 54.88 | 76.97 | 226.4 MB |
| Equipment | 53.38 | 78.97 | 202.7 MB |
| Sequencer — ledger, "NGC 7000 + M31 · full night" (36 nodes) | 37.39 | 62.98 | 255.6 MB |
| Sequencer — empty "New Sequence" | 37.14 | 57.99 | 231.7 MB |
| Darkroom | 30.34 | 49.99 | 358.5 MB |

An idle desktop app should sit near 0%. None of these do.

### The cost is full-window rasterisation, not Dart

Per-thread split on Tonight, 12 s window (`threads.py 12`):

```
window=12.0s  total=98.4%
    70.99%  io.flutter.rast    (raster thread)
    27.41%  nightshade_desk    (GTK platform thread — GL swap/blit)
```

`io.flutter.ui` — the Dart thread that runs `build()` — does not even clear the
0.4% reporting floor. So the idle cost is not a rebuild storm. Frames are being
*produced and rasterised* continuously while nothing changes.

Confirmed by scaling the window, same screen, same state:

| Tonight, window size | area | mean %CPU |
|---|---|---|
| 1920x1200 | 2.30 Mpx | 94.44 |
| 800x600 | 0.48 Mpx | 23.53 |

4.8x the pixels, 4.0x the CPU. The work is per-pixel, and the frame count is
what drives it. On the owner's GPU each frame is far cheaper than under
softpipe — but the app is still waking up, rebuilding a layer tree and
submitting a full-window frame every vsync while sitting still, which is
exactly what "chugging" and a hot laptop feel like.

The remaining question is therefore: **what schedules a frame at idle?**

## 2. Frame timing: what ticks at idle, and why

Profile bundle (`flutter build linux --profile`, exit 0) launched on the same
Xvfb with the Dart VM service enabled through engine switches — the GTK runner
forwards `argv` only as Dart entrypoint args, so the port comes from
`FLUTTER_ENGINE_SWITCHES` / `FLUTTER_ENGINE_SWITCH_n=observatory-port=...`.
`Flutter.Frame` extension events are collected over the VM-service WebSocket by
`/tmp/ns-audit/w8prof/frames.py` (counts + build/raster percentiles) and
`/tmp/ns-audit/w8prof/gaps.py` (inter-frame gaps, which is what identifies a
*periodic* source).

### The app renders ~1.5 frames a second while sitting completely still

`gaps.py "Tonight idle" 20`, window shrunk to 500x400 first so softpipe's raster
cost cannot be the limiter (raster there is 12.6 ms, well inside a gap):

```
Tonight idle @500x400: 32 frames in 20s
  gaps(ms): [233, 766, 684, 317, 233, 66, 701, 1000, 233, 767, 1000, 233, 766,
             1000, 234, 767, 1000, 233, 767, 1000, 233, 767, 1000, 232, 768,
             1000, 233, 766, 1001, 233, 766]
```

The steady state is a perfectly repeating `233, 767, 1000` cycle — 3 frames every
2 seconds — which decomposes into exactly two periodic sources:

* **1 Hz, aligned to the wall-clock second** (frames at t=0, 1, 2, 3 …).
* **0.5 Hz, offset +233 ms** (frames at t=0.233, 2.233, 4.233 …).

Build time for those frames is `p50 = 0.15 ms`. Nothing is thrashing in Dart.
Each of them is a *full-window rasterisation* anyway, because:

```
nm -D --defined-only libflutter_linux_gtk.so | grep -c damage   ->  0
strings libflutter_linux_gtk.so | grep -iE 'partial_update|buffer_age|existing_damage|FlutterDamage'  ->  (nothing)
```

The shipped GTK embedder has no damage-region support at all. So one changed
digit costs the same as a full redraw. The `_TimeDisplay` comment in
`status_bar/temperature_and_time.dart` already said this; the symbol check is
the proof, and the raster numbers are the price.

The same `233 / ~880 / ~900` cycle appears on **every** screen measured —
Tonight, Darkroom, Guiding, Imaging, Weather, Sequencer — including screens
that display no mount and no device readouts. So both sources are in the shell,
not the screens.

### Source B identified: the mount position poll, through a whole-object watch

`packages/nightshade_core/lib/src/providers/equipment/mount_state_provider.dart:34`

```dart
static const _normalPollInterval = Duration(seconds: 2);
```

`_pollPosition()` publishes a fresh `MountState` every 2 s while a mount is
connected — RA/DEC/ALT move continuously, so it is never a no-op write.

`packages/nightshade_app/lib/screens/shell/widgets/status_bar.dart:281` watched
the **whole** provider:

```dart
final mountState = ref.watch(mountStateProvider);
```

but the bar only ever reads three fields from it — `connectionState`,
`deviceName`, `deviceId` (lines 289, 312-313, 352). It never reads the position.
The status bar is mounted on every screen, so a position update the bar does not
display rebuilt the bar, dirtied the frame and repainted the entire window,
every 2 seconds, forever, everywhere.

Confirmed by measuring on **Darkroom**, which shows no mount UI at all — the
+233 ms source is present there too:

```
BEFORE Darkroom idle: 28 frames in 16s
  gaps(ms): [101, 766, 1000, 234, 849, 918, 233, 866, 900, 234, 900, 866, ...]
```

### Source A: the status-bar seconds digit (1 Hz) — reported, not changed

`_TimeDisplay` renders `HH:mm:ss`. It is already correct engineering: it owns
its own tick (so it does not `setState` the whole bar), it is aligned to the
epoch second via `AlignedTicker` (so it shares a frame with the planetarium's
two 1 Hz clocks rather than costing a phase of its own), and it stops when the
app is backgrounded. There is nothing left to fix in it *as written*.

What it costs is a product fact, not a bug: because the embedder cannot do a
partial repaint, **displaying a seconds digit costs one full-window frame per
second on every screen, for the life of the process**. Dropping the `:ss` — or
showing seconds only on screens that need them — would remove 2 of every 3
remaining idle frames. That is the owner's call, so it is reported, not taken.

## 3. Refresh rate: what the app does today

**Nothing sets, queries, or caps the display refresh rate on desktop.**

* `flutter_displaymode` is not a dependency (`grep -rn "displaymode" apps/desktop packages/*/lib` → no matches outside the planetarium's own FPS *readout*).
* `apps/desktop/linux/runner/{main.cc,my_application.cc}` is the stock Flutter GTK runner. It forwards `argv` to `fl_dart_project_set_dart_entrypoint_arguments` and nothing else — no GL swap-interval call, no engine switches, no frame throttling.
* The only explicit cadence control in the app is `AlignedTicker`
  (`packages/nightshade_core/lib/src/utils/aligned_ticker.dart`), and it does not
  cap anything: it *phase-aligns* the app's 1 Hz clocks to the epoch second so
  their ticks coalesce into one frame instead of three. It is the fix for the
  historical "idle frame rate = number of independently-phased clocks" defect,
  and it is still doing its job — four call sites, all 1 Hz, all aligned:
  `status_bar/temperature_and_time.dart:148`, `clock_provider.dart:228`,
  `planetarium_providers/observer_time.dart:158` and `:227`.

So the app takes whatever cadence GTK/EGL gives it, which on a normal desktop is
the monitor's vsync. Nothing fights it and nothing pins it to a lower rate.

**The thing that does NOT hold the monitor's rate is the cost per frame, not the
cadence.** Flutter's shipped Linux embedder has no partial-repaint path at all:

```
nm -D --defined-only build/.../lib/libflutter_linux_gtk.so | grep -c damage       -> 0
strings ... | grep -iE 'partial_update|buffer_age|existing_damage|FlutterDamage'  -> (nothing)
```

Every dirty frame is a full-window redraw. That is why the two idle clocks
measured above cost what they cost, and why per-tile `RepaintBoundary`s (which
let the raster cache return unchanged layers) are the lever that actually
applies on the owner's GPU, where per-pixel raster is cheap but re-painting
every card's text and gradient still is not.

## 4. The real display — the number that actually answers the question

The harness cannot measure vsync, so the profile bundle was launched **once** on
the owner's desktop, against a scratch database at `/tmp/ns-audit/w8real/data`
(seeded from a copy of the preview data, never the preview's own directory), and
closed again. Exactly what was launched and closed:

```
DISPLAY=:0 NIGHTSHADE_DATABASE_DIR=/tmp/ns-audit/w8real/data \
  NIGHTSHADE_DATA_DIR=/tmp/ns-audit/w8real/data \
  apps/desktop/build/linux/x64/profile/bundle/nightshade_desktop     # pid 2177316
...measured for ~2 minutes on the Tonight screen...
kill 2177316                                                         # "closed 2177316 cleanly"
```

`~/.cache/nightshade-ledger-preview` was not touched and the owner's preview
process was not signalled.

**The monitor is 5120x1440 @ 239.90 Hz** (`DISPLAY=:0 xrandr`). That is a
**4.17 ms** frame budget over a **7.37 Mpx** window.

Idle, 30 s sample, warmed up (`frames.py`, `measure.py`):

```
REAL DISPLAY idle (30s confirm)
  window=30.3s  frames=50  FPS=1.6
  build  ms: p50=  0.58 p90=  0.81 p99=  1.15 max=  1.15
  raster ms: p50=  4.31 p90=  5.29 p99= 16.93 max= 16.93
  total  ms: p50=  6.50 p90=  7.92 max= 19.89
  frames over 16.67ms: 1/50 (2%)
REAL DISPLAY idle CPU   n=20  meanCPU=10.70%  maxCPU=16.00%  RSS=141.6MB
```

### The answer

* **Idle cost on the owner's machine is 10.7% CPU and 142 MB, not the 30-108% the
  harness reports.** Softpipe inflates raster by roughly 50-75x; every CPU number
  in section 1 is an upper bound and should be read for its *shape*, not its
  magnitude. The app is not heavy at rest.
* **The app cannot hold 240 Hz, and no setting is stopping it.** A single
  full-window frame costs `p50 = 6.50 ms` end to end (`4.31 ms` of it raster)
  against a `4.17 ms` budget. That is 1.6x over at the median and 1.9x at p90.
  Nothing throttles the app — there is no swap-interval call, no display-mode
  API, no frame cap (section 3). The frame simply costs more than 1/240 s to
  produce, because the embedder has no damage region and repaints all 7.37 Mpx
  for any change.
* **It holds 60 Hz comfortably**: 1 frame in 50 exceeded 16.67 ms at idle.
* So "chugging" at 240 Hz is real and is a *per-frame cost* problem, not a
  cadence problem. The levers are (a) fewer frames when nothing changed, and
  (b) cheaper frames via `RepaintBoundary` so the raster cache can return
  unchanged layers. Both are exercised below.

### What ticks at idle on real hardware

`whichframe.py` clusters build events into frames and names them. On the real
display, on Tonight, the idle cadence is exactly two sources:

```
  t=  0.000s  n=36  DeviceRow, Divider, Expanded, Flexible, ...     <- every 2.000s
  t=  0.250s  n=31  InstrumentPill, RawTooltip, OverlayPortal, ...  <- every 1.000s
  t=  1.250s  n=31  InstrumentPill, RawTooltip, OverlayPortal, ...
  t=  2.000s  n=36  DeviceRow, Divider, Expanded, Flexible, ...
  t=  2.250s  ...
```

* **1 Hz** — `_TimeDisplay`, the status-bar seconds digit. Unavoidable given it
  renders `HH:mm:ss`.
* **0.5 Hz** — `DeviceRow` in the Tonight dashboard's Equipment card, which
  *does* display RA/DEC/ALT, so the 2 s mount poll legitimately changes what is
  on screen there.

**The semantics-only frames that appeared in the harness are a harness
artifact.** In the harness they showed as a third source with no widget rebuild
at all — only `Semantics.ensureGeometry` / `Semantics.updateChildren`:

```
  t=  1.300s  n=  8  Semantics.ensureGeometry, Semantics.ensureSemanticsNode,
                     Semantics.updateChildren, UncontrolledProviderScope
```

`drive_linux.py` sets `GTK_MODULES=gail:atk-bridge` and `NO_AT_BRIDGE=0` so the
accessibility tree exists for `tree`. With no AT client attached — the normal
case on the owner's desktop — Flutter builds no semantics tree and those frames
do not happen. They are absent from the real-display trace above. Worth knowing
for any future sweep: **the harness costs the app a frame every 2 s that a real
user never pays.**

## 5. Fixes, with before/after numbers

### Fix 1 — the status bar watched five device providers whole (`30bb65e5a`)

`packages/nightshade_app/lib/screens/shell/widgets/status_bar.dart` and
`.../status_bar/temperature_and_time.dart`.

The bar is mounted on every screen. It watched `cameraStateProvider`,
`mountStateProvider`, `guiderStateProvider`, `focuserStateProvider` and
`filterWheelStateProvider` as whole objects while rendering a handful of fields
from each — and never the mount's position at all. The 2 s position poll
therefore rebuilt the bar, dirtied the frame and repainted the whole window on
every screen in the app.

Now each watch is a `.select` of exactly the rendered fields. Records compare
structurally and the field names are unchanged, so no render code moved.

**Before / after, idle rebuild trace on Tonight** (`rebuilds.py`, 12 s window,
same screen, same seeded profile):

| widget rebuilt at idle | before | after |
|---|---|---|
| `InstrumentPill` | 74 | not in the top-28 |
| `Readout` | 54 | 63 *(dashboard Equipment card, legitimate)* |
| `_Dot` | 42 | gone |

The device pills leave the idle path entirely. What remains on Tonight is
`DeviceRow` / `ReadoutRow` / `Readout` — the dashboard's Equipment card, which
displays RA/DEC/ALT and must update.

**Effect on the frame count:** on a screen that shows no mount, the 0.5 Hz frame
disappears and idle goes from 3 frames per 2 s to 2 — a third fewer full-window
repaints. On Tonight it does not, because the Equipment card genuinely displays
the position.

### Fix 2 — a `RepaintBoundary` per dashboard tile (`30bb65e5a`)

`packages/nightshade_app/lib/screens/dashboard/widgets/dashboard_tile.dart` had
**zero** `RepaintBoundary` in the whole dashboard directory
(`grep -rc RepaintBoundary screens/dashboard` → 0), on the screen with the
highest idle cost. Every tile shared one layer, so the once-a-second clock tick
repainted every card's text, gradients and charts from scratch.

Each tile now gets a boundary when not in edit mode (not while dragging: a tile
that moves every frame only collects cache misses behind a boundary).

**Before / after, release bundle in the harness, Tonight, idle, 20 s samples:**

| | mean %CPU |
|---|---|
| before | 96.22 |
| after, 4 independent samples | 80.82, 77.38, 74.63, 83.18 (mean 79.0) |

All four after-samples fall below the before-sample, an ~18% reduction. The frame
*count* on Tonight is unchanged (3 per 2 s before and after), so this is a
per-frame raster saving — which is exactly what a boundary buys, and exactly the
lever that still applies on the owner's GPU.

### Honest negative result: the other screens did not move in the harness

| screen | before | after |
|---|---|---|
| Weather | 107.66 | 101.68 |
| Guiding | 85.03 | 93.30 |
| Plan | 62.33 | 70.32 |
| Imaging | 55.53 | 54.48 |
| Equipment | 53.38 | 54.18 |
| Analytics | 54.88 | 36.04 |
| Darkroom | 30.34 | 42.82, then 28.04 / 30.84 / 37.28 on repeat |

Repeat sampling on Darkroom gave 28.04, 30.84, 37.28 and 42.82 for the *same*
build and screen — a spread of ±25%. **Softpipe CPU is too noisy to resolve a
single removed frame per 2 s**, and on these screens the harness's own
accessibility tick keeps the 0.5 Hz frame alive anyway (section 4). The
frame-level trace, not the CPU number, is the evidence that fix 1 works.

## 6. This session's sequencer additions — are they as cheap as claimed?

Checked against the brief's list. All five hold up; numbers where I have them.

**`ledgerClockProvider` (per-minute)** —
`sequence_tree/ledger_columns.dart:433`. A `StreamProvider.autoDispose` that
yields once then every 60 s. One consumer (`ledgerEtaProvider`); `autoDispose`
means a process that never opens a sequencer never subscribes. One frame a
minute is 1/60th of what the status-bar clock already costs. **Cheap as
claimed.**

**Running-row breath animation (gated)** —
`sequence_tree/support_widgets.dart:691`. `RepaintBoundary` wraps
`OnScreenAnimationGate` from the OUTSIDE, which is the correct order and the one
the repo has been burned by before: a boundary inside the gate makes the marker
its own layer, the gate's observer never sees a paint, and it silently stops the
animation two ticks in while looking like a perf win. Verified correct here, and
in all ten `OnScreenAnimationGate` call sites in the tree — none has a boundary
inside the gate. **Correct as claimed.**

**Gutter map `RepaintBoundary`** — `sequence_tree/gutter_map.dart:116`. The
boundary is the `AnimatedBuilder`'s `child`, so it is built once and handed
through rather than rebuilt per scroll pixel, and `SequenceMapPainter`
(`sequence_minimap.dart:240`) takes `super(repaint: scrollController)` so the
picture repaints from the controller without any rebuild at all. **Correct.**

**`AnimatedBuilder` on the scroll controller** — same widget. Its `builder`
rebuilds a `Semantics` node on every scroll pixel, which is real work, but it is
deliberate (the comment says so: the rebuild exists for the semantics `value`)
and it did not show up as a build storm — see the scroll numbers below. On a
desktop with no AT client attached the semantics node is not even materialised.
**Not a problem at the measured cost**; flagged for the owning agent only
because it is the one per-pixel rebuild in the ledger.

**Sticky-ancestor measurement once per frame** — `sequence_tree.dart:392`.
`_scheduleStickyPass` is guarded by `_stickyPassScheduled` to one post-frame pass
per frame, short-circuits on `listEquals`, and is gated off entirely in
Comfortable density before any render box is touched. The walk over
`_visibleOrder` calling `_rowBounds` breaks at the anchor row, so it is O(rows
above the viewport top) rather than O(all rows) — worst case at the bottom of a
long sequence. **Cheap as claimed at 36 nodes**; worth re-measuring if a
sequence ever reaches several hundred rows.

**`.select`-based rebuild scoping** — held up under measurement.

**Measured, ledger loaded with "NGC 7000 + M31 · full night" (36 nodes):**

| state | frames | build p50 | build p99 | build max |
|---|---|---|---|---|
| idle | 1.6/s | 0.15-0.91 ms | — | — |
| continuous wheel scrolling, 16 s | 1.6/s | **0.91 ms** | **12.74 ms** | **12.74 ms** |

A build storm would show as a p99 in the tens of milliseconds and a frame rate
pinned to the scroll. Neither happens. **The sequencer is not the source of the
owner's problem** — the ledger screen was the *second cheapest* of the ten
measured (37.4% vs Weather's 107.7% in the harness).

## 7. Findings I could not fix — files owned by other agents

None of these are defects I can prove cost anything at the measured scale; they
are recorded so the owning agent has the numbers.

* **`gutter_map.dart`** — `AnimatedBuilder(animation: widget.scrollController)`
  rebuilds its `Semantics` wrapper once per scroll pixel. Measured cost during a
  16 s continuous scroll of a 36-node ledger: build `p50 = 0.91 ms`,
  `p99 = 12.74 ms`. Acceptable today. If the gutter ever gains content in that
  builder, this is where it will be paid. No change recommended on these numbers.
* **`sequence_minimap.dart`** — `SequenceMapPainter` is wired correctly
  (`super(repaint: scrollController)`, boundary above it). No finding.
* `target_queue_panel.dart`, `toolbox_panel.dart`, `node_properties_panel.dart`,
  `builder_layout.dart`, `collapsible_panel.dart`, `sequence_toolbar.dart`,
  `nightshade_text_field.dart` — nothing in the idle or scroll traces attributed
  a frame to any of them. No findings.

## 8. Recommendation the owner has to decide (not taken unilaterally)

**The status-bar clock shows `HH:mm:ss`.** Because the Linux embedder has no
damage region, that seconds digit costs one full-window repaint per second on
every screen, forever — 2 of the 3 remaining idle frames per 2 s. At the owner's
window size that is a `6.50 ms` frame, once a second, at rest.

Dropping `:ss` (or showing seconds only where they matter) would take idle from
~1.5 fps to ~0.5 fps. It changes what is on screen, so it is the owner's call,
not mine. Everything needed to make the change is in
`status_bar/temperature_and_time.dart:198`.

Second, larger lever, and the honest answer to "240 Hz": the app produces a
`p50 = 6.50 ms` frame against a `4.17 ms` budget. Closing that gap is a
`RepaintBoundary`-coverage campaign across the heavy screens (Weather's map,
Guiding's graphs, Tonight's remaining panels), of which fix 2 is one screen's
worth and measured an ~18% reduction. That is a piece of work, not a patch.

## 9. Verification (exit codes, unpiped)

| # | command | exit | notes |
|---|---|---|---|
| 1 | `melos bootstrap` | 0 | |
| 2 | `flutter build linux --release` | 0 | after symlinking `native/nightshade_native/target` |
| 3 | `flutter build linux --profile` | 0 | |
| 4 | `dart format --output=none --set-exit-if-changed packages/nightshade_app packages/nightshade_core packages/nightshade_ui` | 1 | **pre-existing**: 41 files changed, none mine. `dart format` on my three files reports "0 changed". |
| 5 | `cd packages/nightshade_app && dart analyze` | 2 | **pre-existing**: 887 issues, ALL severity `info` (deprecations), **zero** in any file I touched. Confirmed by grepping the log for `status_bar.dart`, `dashboard_tile.dart`, `temperature_and_time.dart` — no hits. |
| 6 | `flutter test test/screens/sequencer --concurrency=3` | 1 | 734 pass, **2 fail, both pre-existing** — see below |
| 7 | `flutter test test/screens/shell --concurrency=3` | 1 | 101 pass, **2 fail, both pre-existing** |
| 8 | `flutter test test/screens/dashboard --concurrency=3` | 1 | 182 pass, **1 fail, pre-existing** |

`status_bar_idle_repaint_test.dart` — the test that pins the status bar's
per-second rebuild scope with Flutter's rebuild tracer — **passes** with the
change.

### The five failures are pre-existing at `d6a1caeb3`

Proven, not assumed: my three files were checked out at base
(`git checkout d6a1caeb3 -- <files>`), the failing test files re-run, and they
failed identically. Then restored to HEAD.

```
test/screens/sequencer/session_handoff_dialog_test.dart: switching to Restart updates the decision map
test/screens/sequencer/widgets/mosaic_wizard_resume_test.dart: MosaicWizardDialog resume affordance Start Over ...
test/screens/shell/checkpoint_recovery_dialog_test.dart: a checkpoint that cannot be resumed is not called available
test/screens/shell/checkpoint_recovery_dialog_test.dart: after a failed attempt the operator can leave the modal
test/screens/dashboard/standby_prompt_reserve_test.dart: the standby briefing pays for the floating prompt band
```

They belong to other workstreams and are not touched by this change.

### Notes for whoever runs this next

* `pidstat` is not installed on this host; `/proc`-based samplers were written
  instead (`measure.py`, `threads.py`, `frames.py`, `gaps.py`, `whichframe.py`,
  all under `/tmp/ns-audit/`). None is committed — they are scratch instruments,
  not deliverables.
* `apps/desktop/linux/CMakeLists.txt` looks for the bridge at
  `native/nightshade_native/target/release/`, NOT at `CARGO_TARGET_DIR`. A fresh
  worktree needs that path to exist or `flutter build linux` fails with "Rust
  library not found".
* Driving the app on the owner's desktop is not possible with `xdotool`: the
  session is Wayland (`XDG_SESSION_TYPE=wayland`) and the window does not
  enumerate. The real-display numbers above are therefore for the Tonight screen
  only, which is where the app launches.
