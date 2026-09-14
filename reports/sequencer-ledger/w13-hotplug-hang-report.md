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

