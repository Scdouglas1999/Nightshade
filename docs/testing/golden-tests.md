# Golden / pixel-diff tests

> Owner: CI / build. Companion to `docs/ci-gates.md`.

Nightshade has two kinds of golden test. Only one of them is host-sensitive,
and the strategy below keeps CI trustworthy without throwing away the committed
baselines.

## Two kinds of "golden"

1. **Capture / review goldens** (`docs/design/goldens/`, written by
   `nightshade_ui/test/golden/golden_harness.dart` and
   `nightshade_app/test/golden/surface_golden_harness.dart`). These render a
   real surface and write a PNG for a human to eyeball. **They are NOT
   pixel-diff guards** — the test bodies assert only that a non-empty image was
   produced, so they pass on any host. Nothing special is needed for these.

2. **Pixel-diff / perceptual goldens** — these actually compare rendered pixels
   against a committed baseline and FAIL on a mismatch:
   - `matchesGoldenFile(...)` tests (framing/HiPS render locks, the phone
     `captures_landscape_test.dart` reflow captures, the HiPS fixture mosaic).
   - The planetarium benchmark perceptual gate
     (`nightshade_planetarium/test/benchmark/golden_compare_test.dart`), which
     fails if more than `kGoldenMaxChangedFraction` (0.2%) of pixels differ by
     more than `kGoldenChannelTolerance` (2/255).

   These are **host-specific**: the GPU rasteriser and font hinting differ
   across operating systems, so a baseline captured on one host produces a
   small but real diff on another (observed ~1.0–1.5% for `matchesGoldenFile`,
   ~0.3% changed-fraction for the planetarium gate — both above their
   tolerances). The committed baselines were captured on a Windows host; they
   do not match a Linux renderer.

## The strategy

The pixel-diff tests are tagged **`golden`** (file-level `@Tags(['golden'])`
for whole-file golden suites; a per-test `tags: 'golden'` for the single golden
case inside a file that also holds non-golden geometry guards). The tag is
declared in each package's `dart_test.yaml`.

- **`melos run test`** (what CI's `test-dart` job runs on `ubuntu-latest`, and
  the default local command) passes `--exclude-tags golden`, so the
  host-specific pixel comparisons never run there. Everything else — including
  the non-golden geometry/wiring guards that happen to live in the same files —
  still runs and must pass.
- **`melos run test:golden`** runs ONLY the `golden`-tagged tests. Run this on
  the host the baselines were captured on (today: Windows) to actually exercise
  the pixel comparison.

This was chosen over the alternatives because:
- Mass-regenerating the baselines on Linux would make them pass on Linux but
  fail on the Windows release path and for any Windows contributor — the
  renderer story is genuinely cross-platform, so there is no single host whose
  baselines are "correct" everywhere.
- A loose perceptual threshold large enough to absorb cross-host diffs would
  also absorb the real regressions these tests exist to catch (a dropped star,
  a de-registered FOV reticle).
- Tag-gating mirrors the existing `live-network` opt-in convention already in
  `packages/nightshade_core/dart_test.yaml`, so it is a known pattern in this
  repo.

## Re-baselining

When an intended visual change lands, regenerate the baselines **on the host
the project treats as canonical for goldens** (currently Windows), then commit
the updated PNGs:

```sh
# matchesGoldenFile baselines (per package):
flutter test --update-goldens --tags golden

# planetarium perceptual baselines:
BENCHMARK_GOLDEN_MODE=capture flutter test --tags golden \
  test/benchmark/golden_compare_test.dart
```

If you regenerate on a non-canonical host the new PNGs will fail
`melos run test:golden` everywhere else, so do not commit Linux-rendered
baselines unless the team has decided to move the canonical host to Linux (in
which case re-baseline ALL pixel-diff suites together).
