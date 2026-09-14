# w13-hotplug-hang — live rig freeze, 2026-09-13

Worktree `agent/w13-hotplug-hang` off `preview/ledger-plus-owner-tree` @ `406957c9d`.

## CHECKPOINT 1 — ROOT CAUSE (confirmed, with citations)

The freeze is **not** hot-plug, **not** DepthLock, **not** a Rust lock and **not** the
plate-solve coalescer. It is a **Dart-side whole-sky catalog load on the UI isolate**,
triggered by the **first plate solve of the process that actually SUCCEEDS**.

### The chain

1. Every captured frame auto-runs the annotation pipeline, fire-and-forget, on the UI
   isolate — `packages/nightshade_core/lib/src/services/annotation_service.dart:259`
   (`handleCurrentImageChanged` → `processNewImage(next)`, not awaited).
2. `processNewImage` plate-solves with mount hints
   (`annotation_pipeline.dart:178` `solveWithFallback`). That is the log's
   `Plate solving near RA/Dec`; the blind half of `solveWithFallback` is the second
   request that logs `already being solved; waiting for that result`.
3. **If the solve FAILS it returns early** — `annotation_pipeline.dart:197-202`. Every
   frame from 23:51–23:54 failed (ASTAP: `Only 0/1/2/4 stars found. Abort`, because the
   owner was still focusing — HFR 16 → 5). So annotation never ran and nothing hung.
4. The owner moved the focuser "one last time" → HFR 4.5/3.87, 2171/2469/4400 sources →
   **ASTAP finally solves** (exit 0). ASTAP's success path logs nothing at INFO
   (`native/nightshade_native/imaging/src/platesolve.rs:1070-1094` only logs the
   non-zero-exit failure), which is exactly why all three logs go quiet on the solve
   instead of printing an outcome.
5. Geometry guards pass (`annotation_pipeline.dart:361-379`), `annotateImage` runs
   (`:386`) → `findObjectsInFov` (`:420`) → `annotationCatalog.searchNearby(...)`
   (`:458`) with `searchRadius ≈ 0.69°` (correctly derived, `:433-437`).
6. **`AnnotationCatalog.searchNearby` answers that 0.69° query by loading the ENTIRE
   sky first** — `packages/nightshade_planetarium/lib/src/catalogs/annotation_catalog.dart:392`
   `await loadAll();`.
7. `AnnotationCatalog.loadAll` (`annotation_catalog.dart:292-378`) calls
   `_gladeLoader.loadAll()` (`:346`), which is
   `packages/nightshade_planetarium/lib/src/catalogs/glade_plus_catalog.dart:109`:

       final lines = await file.readAsLines();

   on the GLADE+ catalog. The file's own comment states the scale —
   `glade_plus_catalog.dart:124`: *"GLADE+ carries ~22M entries"*.

### Why this matches every observation

- `readAsLines()` materialises ~22 million Dart `String`s in one `List`, then the parse
  loop allocates a `GladePlusData` + an `AnnotationObject` + **3 strings per row** for the
  dedup key (`'${obj.ra.toStringAsFixed(2)},${obj.dec.toStringAsFixed(2)}'`,
  `annotation_catalog.dart:322-323`, `:350-351`), plus a `Map<String,List>` spatial index.
  That is multiple GB → **3.2 GB working set, still climbing** (heading for OOM).
- Mutator + GC on one isolate → **~1.25–1.7 cores pinned continuously**.
- All of it is Dart. The bridge is never called again → **zero further Rust log lines**.
- The Flutter **platform/message-pump thread is unaffected**, so the Win32 window still
  reports *Responding* while the UI isolate is wedged. 79 threads.
- **One-time per process** (`_mergedCatalog`/`_cachedData` early-returns), so it hangs on
  the FIRST successful solve after every launch — hence the relaunch hung again ~80 s
  later with no device-change event.
- `annotation_catalog.dart` last changed **2026-06-11**, `glade_plus_catalog.dart`
  **2026-08-16** — both long before the owner's Sep 10 build, which is why the rollback
  hung identically. **Pre-existing, not today's work.**

### Secondary O(n^2) in the same function

`annotation_catalog.dart:336` and `:359` — `final index = objects.indexOf(existing);`
is an O(n) linear scan of the growing list, run per colliding row. Against a
multi-million-element list this is quadratic on its own.

### Cleared lines of inquiry (each checked, not guessed)

- **Hot-plug / serial rediscovery**: serial scans are serialised by a *tokio* async mutex
  and run on `spawn_blocking` (`native/.../native/src/vendor/mod.rs:43-71`) — no std lock
  across blocking I/O. Discovery completed normally at 23:57:55, and is entirely absent
  from hangs 2 and 3. **Red herring.** (Real but separate defect: the LX200/Sky-Watcher/
  iOptron scanners do NOT exclude ports owned by connected devices —
  `native/.../vendor/lx200/discovery.rs:29-59` opens every enumerated port. It fails fast
  with ACCESS_DENIED on Windows so it did not cause this hang.)
- **ZWO EAF handle theft by discovery**: already guarded by the connected-device registry
  (`native/.../vendor/zwo/focuser.rs:604-625`) — discovery skips EAFOpen/EAFClose for a
  connected focuser. Not the cause.
- **Plate-solve coalescer**: `coalesced_solve`
  (`native/.../bridge/src/api/plate_solve.rs:105-183`) waits on a
  `tokio::sync::broadcast` receiver with `.await`, has an `InFlightGuard` Drop that clears
  the entry on panic/cancel, and falls back to solving locally on `Err`. The blind-yield
  loop is bounded at 150 ms and uses `tokio::time::sleep`. **No spin, no deadlock.**
  Both solvers run under `spawn_blocking` (`:546`, and the near path).
- **Unified image storage**: a bounded `lru::LruCache`
  (`native/.../bridge/src/api/imaging.rs:632-639`). Not a leak.
- **Double heartbeat** for `native:zwo_eaf:0` (15 s from device_manager + 10 s from
  api::heartbeat): real duplicate registration, logged twice at 23:47:40, but unrelated to
  the freeze. Deferred per coordinator.

### Contributing (not the freeze) — memory

`api_read_fits_file` (`native/.../bridge/src/api/imaging.rs:1484-1556`) is an `async fn`
that does **all** its work synchronously with no `spawn_blocking` and no `.await`, and
returns `display_data` as a full RGBA buffer: `4656*3520*4` = **65.6 MB per call**, plus a
32.8 MB u16 image and a 16.4 MB u8 stretch buffer live at peak (~115 MB per call in Rust,
65.6 MB copied into Dart). The logs show it called **2–3× per frame**, twice
concurrently. `science_processing_service/private_helpers.dart:554` calls it purely to
read five FITS header fields, paying the whole 65.6 MB stretch+RGBA cost to do it.


---

## CHECKPOINT 2 — REVISED ROOT CAUSE (after the 2nd and 3rd hangs)

The coordinator supplied two more hangs: one ~80 s after relaunch with **no
device-change event**, and one on the owner's **Sep 10 build (7.0.0+27, pre-DepthLock)**.
All three logs end with the identical chain. That kills hot-plug and DepthLock outright
and confirms a pre-existing defect. The chain below is the final answer; Checkpoint 1's
mechanism is correct, and the third log let me pin the trigger precisely.

### The trigger: the first plate solve of the process that SUCCEEDS

| log | last frame | our star count | ASTAP outcome logged? |
|---|---|---|---|
| 23:51–23:54 (healthy) | 0001–0008 | 932–1562 | yes — `Only 0/1/2/4 stars found. Abort` |
| hang 1 (23:55) | 0009 | **2171** | **no** |
| hang 2 (00:01) | 0001 | **2469** | **no** |
| hang 3 (00:07) | 0003 | **4341** | **no** |

ASTAP's success path logs nothing at INFO — `native/nightshade_native/imaging/src/platesolve.rs:1070-1094`
logs only the non-zero-exit case. So "no outcome logged" means **the solve worked**. The
owner was focusing: HFR came down 16 → 5 → 4.5 → 3.98, star counts climbed, and the first
frame ASTAP could actually solve is the frame that froze the app. That is why it read as
"I moved the focuser and it died" and why it recurred within ~80 s of every relaunch.

### What a successful solve unlocks

`AnnotationPipeline.processNewImage` runs on every new frame, fire-and-forget on the UI
isolate (`packages/nightshade_core/lib/src/services/annotation_service.dart:259`). It
plate-solves with mount hints (`annotation_pipeline.dart:178`) — that is the log's
`Plate solving near RA/Dec`. **A failed solve returns at `annotation_pipeline.dart:197-202`**,
which is why 8 frames in a row were harmless. On success it runs the geometry guards
(`:361-379`), then `annotateImage` (`:386`) → `findObjectsInFov` (`:420`) →
`annotationCatalog.searchNearby(...)` (`:458`) with `searchRadius ≈ 0.69°` (correctly
derived, `:433-437`).

### The freeze

`AnnotationCatalog.searchNearby` answered that 0.69° query by loading the whole sky first:

- `packages/nightshade_planetarium/lib/src/catalogs/annotation_catalog.dart:392` — `await loadAll();`
- `annotation_catalog.dart:346` — `loadAll()` calls `_gladeLoader.loadAll()`
- `packages/nightshade_planetarium/lib/src/catalogs/glade_plus_catalog.dart:109` —
  `final lines = await file.readAsLines();`

with the file's own comment at `glade_plus_catalog.dart:124` stating the scale:
**"GLADE+ carries ~22M entries"**.

`readAsLines()` materialises ~22 million Dart `String`s in one list; the loop that follows
is **synchronous** and allocates a `GladePlusData`, an `AnnotationObject` and **three
strings per row** for the dedup key (`annotation_catalog.dart:322-323`, `:350-351`), then
builds a whole-sky `Map<String,List>` index. Consequences, all matching the rig exactly:

- **UI frozen, Win32 window still "Responding"** — the synchronous loop never yields, so
  no other microtask on the UI isolate ever runs again. The Flutter platform/message-pump
  thread is untouched, so Windows still sees a responsive window.
- **No further log output** — the isolate never gets back to any code that calls the
  bridge, so the native log simply stops mid-chain. The last line landing on a FITS read
  is incidental: it is wherever the concurrent science lane happened to be.
- **~1.25–1.7 cores** — one mutator at 100% plus Dart GC helper threads.
- **3.2 GB and climbing** — heading for OOM, not a steady state.
- **Once per process** (`_mergedCatalog`/`_cachedData` early-return), so it reproduces on
  the first successful solve after *every* launch.
- **Pre-existing**: `annotation_catalog.dart` last changed 2026-06-11,
  `glade_plus_catalog.dart` 2026-08-16 — both well before the Sep 10 build, which is why
  the rollback hung identically.

Secondary, same function: `annotation_catalog.dart:336` and `:359` resolved each position
collision with `final index = objects.indexOf(existing);` — an O(n) scan of the growing
merged list, i.e. quadratic in colliding rows on top of being whole-sky.

### Why the two concurrent solves are in the log but are not the bug

Two Dart lanes solve the same frame: the annotation lane (hinted, leads) and the science
lane's `solveForScience`, which calls `_backend.plateSolve` directly and so bypasses the
Dart single-flight gate (`packages/nightshade_core/lib/src/services/science/default_science_backend.dart:56-63`).
The **Rust** coalescer caught what the Dart gate missed and logged
`already being solved; waiting for that result` — `native/.../bridge/src/api/plate_solve.rs:105-183`.
That code is sound: a `tokio::sync::broadcast` receiver awaited (no spin), an
`InFlightGuard` Drop that clears the entry on panic/cancel, a local-solve fallback on
`Err`, a blind-yield loop bounded at 150 ms using `tokio::time::sleep`, and both solvers
under `spawn_blocking`. **Cleared.**

## THE FIX

### 1. Region-scoped streaming catalog queries (the freeze)

New `packages/nightshade_planetarium/lib/src/catalogs/catalog_region_scan.dart`:
`CatalogRegionFilter` (cone + magnitude test, primitives only so it is isolate-sendable)
and `scanCatalogRegion`, which streams the file
(`openRead().transform(utf8.decoder).transform(LineSplitter())`) and keeps only rows
inside the cone, with a `maxResults` backstop and malformed-row counting reported once
instead of logged per row.

- `glade_plus_catalog.dart` — `loadAll`, `_cachedData`, the whole-sky `_spatialIndex` and
  `clearCache` are gone. `searchNearby` now runs `scanGladePlusRegion` inside
  `Isolate.run`. Peak memory is proportional to the answer; the UI isolate never parses.
- `hyperleda_catalog.dart` — the same treatment for its cone query (identical trap, ~3M
  rows). Its by-name helpers still use `loadAll`, because a name lookup genuinely has to
  consider every row; the unread spatial index was removed with its only reader.
- `annotation_catalog.dart` — `searchNearby` queries each backing catalog for the region
  only and merges in priority order, keying collisions through a `Map<String,int>` so a
  merge is O(1) instead of `List.indexOf`. The whole-sky `loadAll`, `_mergedCatalog`,
  `_spatialIndex`, `_gridKey`, plus the unreachable `search`/`count` that depended on
  them, are removed. The public shape `annotation_pipeline` and the existing
  `_ThrowingAnnotationCatalog` test double rely on is unchanged.

The scan also fixes two latent correctness bugs it inherited: the cone test now wraps RA
across the 0h/24h seam (a plain subtraction dropped half a field straddling RA 0), and
`positionOf`/magnitude filtering are applied before anything is retained.

### 2. The 3.2 GB texture leak (contributing, separate defect)

`packages/nightshade_app/lib/screens/imaging/widgets/image_display.dart` replaced
`_decodedImage` on every frame and had **no `dispose()` at all** — the only image widget
in the app that omits it, and the one mounted at native resolution on the Imaging screen.
A `ui.Image` holds its texture off the Dart heap, so dropping the reference leaks it:
**65.6 MB per captured frame** at 4656×3520 (≈45-50 frames to reach 3.2 GB). Now disposes
the replaced image, disposes on the unmounted decode path, and disposes in `dispose()` —
the pattern every sibling already uses (`live_stack_canvas.dart:334-335,379`,
`centering_dialog/image_canvas.dart`, `stacking_panel/stacked_preview.dart`,
`darkroom_screen_parts/_image_surface.dart`, `widgets/astro_image_viewer.dart`).

### Tests

- `packages/nightshade_planetarium/test/catalog_region_scan_test.dart` — 15 tests: cone
  geometry, cos(dec) compression, RA-seam wrap, magnitude cutoff, missing-magnitude
  convention, header skip, malformed-row tolerance, missing-file error, **answer
  proportional to the cone not the catalog**, **the calling isolate keeps being serviced
  for the whole scan** (periodic timer, not a one-shot — a one-shot could slip through the
  old code's awaited `readAsLines`), and truncation under a pathological radius.
- `packages/nightshade_planetarium/test/annotation_catalog_region_merge_test.dart` — 7
  tests: region scoping, brightest-first ordering, collision collapse, magnitude cutoff,
  type filter, unavailable with no loaders, and 4,000 colliding rows completing promptly
  (quadratic under the old `indexOf` merge).
- `packages/nightshade_app/test/screens/imaging/image_display_texture_release_test.dart` —
  2 tests: the replaced texture is released, and the live texture is released on dispose.
  Both **verified to fail** with the dispose calls removed
  ("the replaced texture was leaked" / "the texture outlived the widget that owned it").

### 3. Cached field, so the fix does not trade a freeze for a stall

Removing the whole-sky load alone would mean a background re-read of a
multi-gigabyte catalog on every frame, because the annotation pipeline queries once per
captured frame. `CatalogRegionCache` in `catalog_region_scan.dart` memoises the last
scanned field: each scan covers a cone padded to `radius * 1.5 + 0.1` and is
**magnitude-blind**, so the next frame — whose centre has drifted slightly and whose
SNR-based magnitude cutoff moves frame to frame
(`annotation_pipeline.dart:305-312`) — is enclosed and answered from memory.
Containment uses a true spherical separation (`CatalogRegionFilter.separationDegrees`),
not the small-angle form, because the small-angle approximation is not safe for deciding
whether one cone encloses another. A truncated scan is never cached, since it does not
honestly represent its cone. `clearCache()` on either loader drops it, and
`AnnotationCatalog.clearCache()` still reaches all three loaders, so a re-imported
catalog file is read afresh.

Four more tests cover it: a narrower later cone served from memory (proved by deleting
the file first), a deeper magnitude cutoff still answered correctly, a cone outside the
scanned field re-read rather than guessed, and `clearCache()` forcing a re-read.
