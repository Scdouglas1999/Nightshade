# Planetarium Atlas & Performance — design and verification record

Date: 2026-06-06
Branch: `roadmap/planetarium-atlas-and-perf`
Package: `packages/nightshade_planetarium` (the go-forward v1 line; the scrapped v2 is dead)

> Location note: `docs/plans/` is gitignored in this repo (no plan docs are
> tracked there), so this design record lives under the tracked `docs/design/`
> tree alongside the other committed design docs and goldens.

This document records the two pillars of the work, the balanced feature set that
shipped versus what was deliberately deferred, the benchmark methodology, and the
authoritative before/after numbers with the golden anti-cheat gate confirmation.

---

## 1. The two pillars

This branch advances the planetarium along two independent axes that share one
deterministic measurement spine:

1. **Atlas / capability** — make the planetarium a genuine session-planning
   instrument: astronomy that is correct to the minute, on-sky planning overlays,
   a backyard-horizon-aware scoring model, multi-rig framing, an alt/az "tonight
   from my site" view, a unified search, and a measurement tool. These are the
   user-facing reasons to open the planetarium when composing a night.

2. **Performance** — keep the dense planning view cheap to paint, and — more
   importantly — make performance *measurable and defensible*. The headline
   deliverable of the perf pillar is not a one-off speedup; it is a committed,
   deterministic benchmark harness plus a perceptual-golden anti-cheat gate, so
   that every future change to the paint pipeline has an attributable, reproducible
   effect and cannot "optimize" by silently rendering less.

The design stance throughout: clean, schematic, precision-instrument. No realistic
DSO photo imagery in the planetarium (survey/HiPS imagery lives in Framing). All new
chrome uses the `packages/nightshade_ui` design-system tokens.

---

## 2. Feature set — shipped vs deferred

### Shipped (7 of 7 planned features, all committed)

| # | Feature | Commit | What it does |
|---|---------|--------|--------------|
| 1 | Accurate body-aware rise/transit/set + precession + twilight | `725aa052` | Iterative, body-aware (moving-Sun/Moon) rise/transit/set converging to sub-minute, IAU precession + nutation mean obliquity, real twilight (civil/nautical/astronomical) — replaces the old static approximation. |
| 2 | On-sky meridian-flip + twilight + altitude-track overlays | `11c8acf3` | Draws the meridian-flip line, the dusk/dawn twilight band, and a target's altitude track directly on the sky — the night composed visually, not in a table. |
| 3 | Backyard horizon mask → target scoring + `.hor`/CSV import | `fe295a16` | The 360-entry horizon profile (importable from `.hor`/CSV) feeds `target_scoring.dart` so a tree-line or building actually lowers a target's hours-visible/score, not just the painter's horizon cutout. |
| 4 | First-class multi-rig FOV framing presets | `915683c5` | Named per-rig FOV presets (camera sensor rectangle + Telrad + eyepiece circle), multiple overlays at once, rotation — `fov_presets.dart` + `multi_fov_overlay.dart`. |
| 5 | Alt/Az "tonight from my site" view mode | `d3c01972` | A horizon-referenced alt/az projection mode for "what is up right now from where I stand", distinct from the equatorial atlas view. |
| 6 | Unified search omnibox + smooth fly-to GoTo | `eb0f54b4` | One search box resolving catalog ids, common names (fuzzy), star ids, and solar-system bodies to a single object, with an eased fly-to. |
| 7 | Angular measurement tool (separation + position angle) | `3b2c408a` | Tap-to-tap angular separation and position angle on the sky, readout kept on-screen; follow-up fix `f103c86d` corrects fly-to in alt/az mode and keeps the readout pinned. |

All seven reuse Feature-1's accurate astronomy (`astronomy_calculations.dart`); none
reintroduce the prior approximation. Each landed with its own unit/widget tests
(rise_set_transit, planning_overlays_render, target_scoring_horizon_mask,
fov_presets, multi_fov_overlay, alt_az_view_mode, search_resolver,
angular_measurement).

### Deferred (deliberately out of scope — network/data-heavy)

* **Deep-star Gaia/Tycho magnitude tier.** Extending the stellar atlas below the
  HYG ~mag 13 floor to a Gaia/Tycho deep tier is a large bundled-data and
  streaming/LOD problem. It would change the atlas's data footprint and paint
  characteristics enough to warrant its own design pass and its own benchmark
  fixture; bolting it on here would have made the perf pillar's before/after
  un-attributable. Deferred.

* **Live MPC / TLE refresh.** Pulling fresh minor-planet elements (MPC) and
  satellite TLEs at runtime is a network + cache-invalidation + offline-fallback
  feature, orthogonal to the schematic-rendering and planning work on this branch.
  The existing committed elements/SGP4 path stays; live refresh is deferred to a
  data-services effort.

Both deferrals are about keeping this branch a self-contained, offline,
deterministically-measurable unit. Neither is blocked by anything shipped here.

---

## 3. Benchmark methodology

The perf pillar's foundation is `packages/nightshade_planetarium/benchmark` (harness
`0924d1cd`, baseline `a95639da`). It has three layers, by design:

### 3.1 Deterministic CPU-rasterization-time proxy (the optimization signal)

`test/benchmark/paint_benchmark_test.dart` builds the **real** `SkyCanvasPainter`
(+ `FOVOverlayPainter`), records `paint()` into an offscreen `PictureRecorder`,
**rasterizes the recorded display list to a real bitmap** (`Picture.toImage`), and
**reads the pixels back** (`Image.toByteData`) — each step timed with a
high-resolution `Stopwatch`. This includes the actual fill / blend / glow-blur /
atlas-blit cost, run through the software rasterizer under `flutter test`. It is a
CPU-side *proxy* for on-device GPU cost: directionally faithful for overdraw / fill
rate / blend, and deterministic and low-noise (~1% run to run). It deliberately
excludes the real on-display GPU and vsync, so it is **not** an FPS measurement;
`avgFps` in the JSON is the raster-bound ceiling `1000/meanMs`, not on-display FPS.

> **Methodology correction (commit `89bad14f`).** The original harness timed only
> `PictureRecorder.endRecording()` — i.e. *display-list recording*, the cost of
> building the Skia op list. That finished in ~1 ms regardless of scene weight
> (p95 ≈ 1.9 ms on the feature-complete scene) and was **blind to rasterization**:
> the overdraw, blend and glow-blur passes an optimization actually changes were
> never measured, and the number was noise-dominated. As a result the first
> optimization pass against that signal found nothing actionable — there was no
> real cost to attack in the measured quantity. `89bad14f` fixed the metric to
> rasterize-and-read-back, which exposes a stable **~33.6 ms p95** worst-case
> signal (median of ≥3 runs, ~1% spread). All numbers in §4 below are under this
> **corrected** metric; the pre-`89bad14f` ~1.9 ms figures are obsolete and have
> been removed.

Determinism comes from:
* A committed seeded fixture (`fixtures/stress_scene.json`, seed `0x5EED5301`):
  14,000 stars (steep faint-end power law), 900 mixed DSOs, 18 constellation
  figures, the Milky Way band, every coordinate grid, Sun/Moon/4 planets, the
  twilight band gauge drawn every frame, and a rotated FOV preset (camera rect +
  Telrad + eyepiece). The benchmark **loads** the JSON; it never regenerates at run
  time.
* A scripted 180-frame camera timeline (`camera_timeline.dart`): wide → pan → deep
  zoom → hold while simulated time advances ~30 min → zoom out → pan home. No wall
  clock feeds any timing input; simulated time is a fixed offset from the fixture
  base time.

Output is `benchmark/results/latest.json` (gitignored, a fresh artifact each run)
with a stable key contract `{p50Ms, p95Ms, p99Ms, avgFps, rssMb, objectsDrawn,
frames, scene, note}`.

### 3.2 Perceptual-golden anti-cheat gate

`test/benchmark/golden_compare_test.dart` renders 5 checkpoint frames (wide start,
mid-pan, deep zoom, post-time-advance, wide return) and perceptually diffs a fresh
render against committed baselines under `benchmark/goldens/`.

* Channel tolerance = 2/255 (treat ≤2 per-channel delta as AA jitter).
* Fail if > 0.2% of pixels exceed that tolerance.

This is the anti-cheat: any "optimization" that improves paint time by dropping a
star, label, glow, or line moves far more than 0.2% of pixels and fails. Pure
AA/rounding jitter stays well under both thresholds (in fact headless re-renders here
are byte-identical, maxDelta=0). A timing win is only accepted if this gate stays
green.

### 3.3 Real on-display FrameTiming (the reality check)

`integration_test/frame_timing_test.dart` drives an animated widget and reads real
build+raster milliseconds (GPU included) via `FrameTiming` on a machine with a
display. This is **not** a CI/loop gate — it needs a display and varies with the host
GPU — it is the manual sanity check that the CPU-proxy story matches reality.

The split is deliberate: the headless number is the reproducible optimization signal;
the integration number is the on-hardware reality check.

---

## 4. Before / after (corrected metric)

All numbers are from the headless **CPU rasterize-and-read-back proxy** (balanced
quality, 1280×800, 180 timed frames, warm-up excluded), under the corrected metric of
§3.1. They are **CPU rasterization milliseconds, not on-display FPS.** Each row is the
**median of 3 runs** (single-run spread ~1%), per the noise discipline.

| Stage | Scene | p50 (ms) | p95 (ms) | p99 (ms) | avgFps (raster ceiling) | rss (MB) |
|-------|-------|---------:|---------:|---------:|------------------------:|---------:|
| `post_feature` / `best` (feature-complete reference) | twilight band gauge + FOV preset every frame | 18.18 | **33.566** | 37.095 | 49.8 | 184.6 |
| `latest` (fresh 3-run median, this verification) | feature-complete (same scene) | 17.536 | **31.122** | 35.781 | 52.5 | 177.9 |

### Reading the table honestly — no safe optimization win was found

**The optimization pillar did not produce a paint-time speedup, and this document
will not pretend otherwise.**

* The renderer (`lib/rendering/**`, `lib/widgets/interactive_sky_view.dart`) is
  **byte-for-byte unchanged** between the feature-complete freeze (`bd062b65`) and
  HEAD — `git diff bd062b65 HEAD -- lib/rendering lib/widgets/interactive_sky_view.dart`
  is empty. The only commit after the freeze touching the perf pillar is `89bad14f`,
  which fixed the **benchmark**, not the paint code. `best.json` therefore still
  equals `post_feature.json`: no pass cleared the "beat the reference by ≥5% over ≥3
  runs without failing the golden gate" bar that overwrites the champion.
* The first optimization attempt ran against the **broken** recording-only metric
  (§3.1) and correctly found nothing: the quantity being measured (~1.9 ms display-
  list build) had no rasterization cost in it to attack. Fixing the metric
  (`89bad14f`) revealed the real ~33.6 ms p95 worst-case cost, but the candidate
  wins that remained were all **forbidden by the golden anti-cheat gate** — they
  reduced what is drawn (fewer faint stars, coarser glow, dropped labels, lower
  magnitude limit, reduced resolution), which is visual-quality loss, not
  optimization. The prior v1 perf rework this branch builds on had already taken the
  free, lossless wins (static/animated `RepaintBoundary` split, cull-before-project,
  `drawRawAtlas` sprite atlas, projection cache, scratch buffers); no further
  pixel-identical structural win was found within this phase's scope.
* The **~7% p95 difference** in the table (`33.566 → 31.122`) is **host/run variance
  on the CPU proxy, not an optimization.** Because no paint logic changed, the only
  cause is run-to-run drift; the corrected metric's ~1% per-run noise plus
  cross-session host load comfortably spans this. It does **not** clear the ≥5%
  champion-overwrite bar in a way attributable to code, so `best.json` is left at the
  reference and is **not** overwritten by this verification.

What the perf pillar actually delivers is the **defensible measurement spine**: a
committed deterministic stress fixture + scripted camera timeline, a *corrected*
rasterize-and-read-back signal that is responsive to overdraw/fill/blend/glow/atlas
cost (the thing future optimization must move), and a perceptual-golden anti-cheat
gate that makes "optimize by rendering less" fail loudly. That is the honest
deliverable; there is no fabricated speedup over the feature-complete scene.

### Visual quality preserved — golden gate green

The perceptual-golden gate is the proof that the richer scene did not silently lose
fidelity. Fresh compare run, all 5 checkpoints:

```
00-wide-start:    maxDelta=0 changed=0.0000% (limit 0.20%) OK
01-mid-pan:       maxDelta=0 changed=0.0000% (limit 0.20%) OK
02-deep-zoom:     maxDelta=0 changed=0.0000% (limit 0.20%) OK
03-time-advanced: maxDelta=0 changed=0.0000% (limit 0.20%) OK
04-wide-return:   maxDelta=0 changed=0.0000% (limit 0.20%) OK
All tests passed!
```

`maxDelta=0` / `changed=0.0000%` across every checkpoint: the feature-complete render
is pixel-identical to the committed feature-complete goldens. Visual quality is
preserved.

---

## 5. Verification gates (re-run for this record, corrected metric)

* Headless benchmark (`paint_benchmark_test.dart`), **3 runs, median reported**:
  **pass** — p95 = 31.122 / 30.947 / 32.761 ms (median **31.122**), p50 median
  **17.536**, p99 median **35.781**, avgFps median **52.5**, rss median **177.9 MB**.
  Reference `post_feature.json` p95 = 33.566 ms; the ~7% delta is host/run variance
  (no paint code changed — see §4), so `best.json` is **not** overwritten.
* Golden compare gate (`golden_compare_test.dart`): **pass** — 5/5 checkpoints
  byte-identical, `maxDelta=0 changed=0.0000%` (limit 0.20%). Visual quality
  preserved; no "render less" cheat.
* `flutter analyze` `packages/nightshade_planetarium`: **0 errors** (129 pre-existing
  infos/test-file warnings only — e.g. `catalog_parsing_test.dart`
  unused-param/`coordinate_system_test.dart` prefer-const, all under `test/`; **no
  lib warnings introduced**).

No renderer or `nightshade_app`/`nightshade_ui` source change was made in this phase
(benchmark fix + doc record), so those suites were not re-run for this record.
