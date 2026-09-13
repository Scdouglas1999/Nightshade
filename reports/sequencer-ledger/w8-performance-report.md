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

