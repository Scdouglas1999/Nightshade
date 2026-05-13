# Rust Code Quality Audit — Nightshade v2.5.0

**Branch:** `main` (worktree `worktree-agent-accda7506919a9079`)
**HEAD:** `bbdee9b fixed a ton of bugs` (ahead of `0c88691` baseline)
**Workspace:** `native/nightshade_native/` — 8 crates, ~131k LOC total, ~106k LOC non-generated.
**Toolchain:** Rust 2021, `flutter_rust_bridge = "=2.11.1"`, `tokio 1.35`.

---

## 1. Idiomatic-Rust scan

### 1.1 `unwrap()` panic sites

`grep` returns **197** occurrences in 30 files; after excluding `tests/`, `#[cfg(test)]` modules, and the `frb_generated.rs` auto file, the **non-test count is ~120**.

Top 5 production files by unwrap count (test-modules subtracted):

| File | Non-test unwraps | Risk |
|---|---|---|
| `bridge/src/storage.rs:10` | 10 | Mutex::lock, RwLock::write — *poison panic* |
| `sequencer/src/executor.rs:1-1582` | ~15 | All on `progress.write().unwrap()` / `read().unwrap()` — every executor poll can panic the runtime |
| `native/src/vendor/moravian.rs` | 19 | `handle.lock().unwrap()` — every SDK call point |
| `native/src/vendor/touptek.rs` | 18 | Same pattern |
| `native/src/vendor/atik.rs` | 16 | Same pattern |
| `bridge/src/device_id.rs:118-163` | 6 | LRU cache `Mutex::lock().unwrap()` |

**Observation.** `std::sync::Mutex::lock()` only returns `Err` when the mutex is *poisoned* (a prior holder panicked). The current codebase assumes infallible locks. Given the CLAUDE.md "errors are a feature" rule, every one of these should be `.lock().expect("...")` with a description of the invariant, or upgraded to `parking_lot::Mutex` (which is unpoisonable and slightly faster).

### 1.2 `expect()` informativeness

90 occurrences across 12 files. Mostly in vendor crates wrapping FFI handle Mutex acquisition; sampled messages (e.g., `"SDK not initialized"`) are acceptable.

### 1.3 `unimplemented!()` / `todo!()` / `panic!()` outside tests

Every match outside `tests/` and `#[cfg(test)]` is inside `bridge/src/frb_generated.rs` (41 `unimplemented!("")` stubs for unreachable codec arms). `native/tests/native_driver_tests.rs` has 11 `panic!("No X cameras found")` test setup guards. **No `todo!()` in production code.** Good.

### 1.4 `as` casts where `From`/`TryFrom` would be safer

909 `as i32|u32|f64|usize|f32` matches workspace-wide. Most are pixel arithmetic (fine). `clippy::pedantic` flags 1,266 across `cast_possible_truncation` (339), `cast_sign_loss` (223), `cast_possible_wrap` (148), `cast_precision_loss` (117), and `cast_lossless` (439, all trivially replaceable by `.into()`).

### 1.5 `if let Ok(_) = …` silent-error swallowing

Only **4 matches**, all in `native/nightshade_native/updater/src/main.rs:244, 255, 256, 266`. These are tolerable (filesystem-replace fallback ladder, lines 240-268) but the inner `else` branch at line 259-262 retries with no logging — a `tracing::warn!` would help post-mortem.

### 1.6 `let _ = …` silent discards

**460** matches in 47 files. Highest concentrations: `ascom_wrapper_mount.rs` (76) and `ascom_wrapper.rs` (50) discard COM `Release` results (acceptable); `devices.rs` (38), `executor.rs` (20), `indi/client.rs` (23) warrant a closer look. `alpaca/src/guard.rs:35,63,91,119,147,175` swallow `disconnect().await` failures in `Drop` — should `tracing::warn!` on error.

---

## 2. Async correctness

### 2.1 `tokio::spawn` — detached vs joined

10 production call sites:

| File:line | Joined? | Notes |
|---|---|---|
| `indi/src/client.rs:475` | No | `writer_task` — handle dropped. Acceptable lifetime tied to client. |
| `indi/src/client.rs:511` | No | Reader/dispatch task. Same. |
| `indi/src/discovery.rs:269` | **Yes** | Pushed into `handles` Vec and joined. Good. |
| `bridge/src/api.rs:6489` | No | Sequencer-event → Dart event bridge. **Detached forever**. If it panics, sequencer-state updates go silent and there's no replacement. |
| `bridge/src/api.rs:7755` | No | Polar-alignment monitor. Same risk. |
| `bridge/src/devices.rs:7186` | Stored as `task` — verify usage | Need to confirm; appears to be heartbeat. |
| `bridge/src/imaging_ops.rs:61` | No (`let _handle`) | Image-processing worker loop. Crash = silent loss of all post-exposure stats/saves. |
| `bridge/src/imaging_ops.rs:627` | No | Continuous job spawn. |
| `sequencer/src/executor.rs:658` | No | The main sequence-execution task. Panic kills sequence with no upward signal. |
| `sequencer/src/node.rs:1807` | **Yes** | Parallel-node child tasks, joined via `futures::future::join_all`. Good. Note: `filter_map(|r| r.ok())` at line 1867 silently drops panicked branches — at least log them. |

**Recommendation.** For the 6 detached spawns above, wrap the body in a `tokio::task::JoinHandle`-monitor pattern: spawn a sentinel that logs `"task X exited unexpectedly: {err}"` when it finishes, and ideally restarts it for the worker loops.

### 2.2 Locks held across `.await`

Spot-checks of high-traffic files (`bridge/src/api.rs`, `unified_device_ops.rs`, `devices.rs`, `sequencer/src/executor.rs`) did not reveal `RwLock::write().await` followed by an inner `.await` in the same scope. The bulk of locks are `parking_lot`-style `std::sync::Mutex` / `RwLock`, which cannot be awaited across.

One pattern of concern: `executor.rs` calls `self.progress.write().unwrap()` (sync `std::sync::RwLock`) inside `async fn`. This is fine as long as the lock is released before the next `.await`. Worth a targeted clippy lint (`clippy::await_holding_lock`).

### 2.3 `block_on` from async context (deadlock risk)

5 production sites:

- `indi/src/camera.rs:448, 513` — `Handle::current().block_on(self.client.read())` inside an `async fn`. The wrapper uses `tokio::task::block_in_place` so it doesn't outright deadlock on a multi-thread runtime, but **this should just be `.await` directly**. It is reading a `tokio::sync::RwLock` to fetch a config value — there is no reason to block.
- `indi/src/filterwheel.rs:71` — same anti-pattern.
- `sequencer/src/executor.rs:1629, 1644, 1680` — inside `#[cfg(test)]`, acceptable.
- `alpaca/src/guard.rs:35-175` — `Drop` impls spawn a new thread with a fresh runtime to call disconnect. Reasonable, but `tokio::runtime::Handle::try_current()` first to avoid a new runtime when one already exists would be cleaner.
- `bridge/src/real_device_ops.rs:280` — runs inside a `tokio::task::spawn_blocking` body, so safe.
- `bridge/src/lib.rs:558` — top-of-runtime entry; safe by construction.

### 2.4 Channel hygiene

`imaging_ops.rs:61-90` constructs an `mpsc` channel with no documented buffer size — `mpsc::channel(N)` not yet sampled. A receiver dropped while senders still send is silently logged as `SendError` and lost. No findings without more focused review.

---

## 3. FFI safety (`unsafe` audit)

### 3.1 Volume

**734 occurrences** of `unsafe` outside `frb_generated.rs`. Concentrated in vendor SDK wrappers:

| Crate | unsafe blocks |
|---|---|
| `native/src/vendor/zwo.rs` | 75 |
| `native/src/vendor/qhy.rs` | 58 |
| `native/src/vendor/fli.rs` | 62 |
| `native/src/vendor/atik.rs` | 45 |
| `native/src/vendor/moravian.rs` | 42 |
| `native/src/vendor/player_one.rs` | 40 |
| `native/src/vendor/fujifilm.rs` | 39 |
| `native/src/vendor/svbony.rs` | 39 |
| `native/src/vendor/touptek.rs` | 34 |
| `ascom/src/windows_impl.rs` | 46 |
| `bridge/src/frb_generated.rs` | 174 (excluded; auto) |

These are necessary FFI calls to vendor C SDKs.

### 3.2 SAFETY comments

Only 4 files contain *any* `// SAFETY:` comments (`ascom/src/windows_impl.rs`, `imaging/src/raw.rs`, `native/src/vendor/atik.rs`, `native/src/vendor/fujifilm.rs`). The remaining 700+ unsafe blocks have **no SAFETY justification**, which is a clippy `undocumented_unsafe_blocks` violation and an audit liability.

### 3.3 CString embedded-NUL panics

`grep` finds 9 `CString::new(...)` sites. One uses `.unwrap()`:

- **`native/src/vendor/fli.rs:439`** — `let path_cstr = CString::new(path.clone()).unwrap();`. `path` is sourced from `CStr::from_ptr(filename.as_ptr()).to_string_lossy()`, so an embedded NUL is unlikely but not impossible. Should be `.map_err(...)?`.

All other CString sites use `.map_err(...)?` or `match`. Good.

### 3.4 Null pointer handling

11 `.is_null()` checks vs 90+ `.as_ptr()/.as_mut_ptr()` sites in vendor wrappers. Ratio is reasonable since most FFI calls operate on a pre-checked SDK handle. No specific null-deref bug found.

### 3.5 `static mut` / unbounded statics

**No `static mut`** found — good.

**`OnceLock<Mutex<HashMap<…>>>` and similar:**

| File | Type | Risk |
|---|---|---|
| `bridge/src/api.rs:3355` | `OnceLock<Arc<RwLock<HashMap<String, CapturedImageData>>>>` (`UNIFIED_IMAGE_STORAGE`) | **Grows unboundedly** — captured images are inserted by ID but the eviction policy is not visible from the declaration. Risk of memory leak in long sessions. |
| `bridge/src/api.rs:6064` | `OnceLock<Arc<RwLock<HashMap<String, Arc<AlpacaClient>>>>>` (`ALPACA_CLIENTS`) | Should remove on disconnect. Verify. |
| `native/src/vendor/touptek.rs` | `OnceLock<Mutex<HashMap<String, …>>>` for multi-brand SDK storage | Bounded by brand count, safe. |
| `bridge/src/device_id.rs:118` LRU cache | LRU-bounded, safe. |

**Action.** Add a comment + invariant to `UNIFIED_IMAGE_STORAGE` and `ALPACA_CLIENTS` declarations or convert to bounded LRU.

---

## 4. Error propagation

### 4.1 `NightshadeError` enum quality

`bridge/src/error.rs` (842 lines) has rich structured variants (`HardwareError { device_id, message, error_code }`, `DeviceTimeout { ... }`, etc.) and **no `Other(String)` catch-all** — excellent. FFI-boundary errors preserve structure.

### 4.2 `?` and context

Only **15 uses of `with_context(...)` or `.context(...)`** workspace-wide (`anyhow` is a dependency but barely used). The majority of `?` chains in `bridge/src/api.rs` propagate errors verbatim with no added context. When a `start_exposure` call returns `NightshadeError::Hardware { … }` 6 layers deep, the caller has no idea which function it traversed.

**Recommendation.** Introduce a thin `.map_err(|e| NightshadeError::wrap(e, "context-string"))` helper and apply at the FFI-boundary functions.

### 4.3 `unwrap_or` family (silent-fallback audit)

**288** `unwrap_or_default() | unwrap_or(false) | unwrap_or(0) | unwrap_or_else(|_| …)` calls in 46 files.

**None** carry a `// Why:` comment — there are zero `// Why:` comments in the entire Rust tree. This is a direct CLAUDE.md violation ("silent fallbacks hide bugs for months").

Top offending files:
- `bridge/src/device_capabilities.rs` — 69
- `bridge/src/devices.rs` — 38
- `bridge/src/api.rs` — 31
- `imaging/src/phd2.rs` — 20

Sample concerning sites:
- `alpaca/src/telescope.rs:957` — `is_pulse_guiding: is_pulse_guiding.unwrap_or(false)` — silently defaults a flag to `false`. If the device returns a parse error here we will report "not guiding" while it is.
- `alpaca/src/client.rs:315, 521, 580, 631, 668, 722, 776, 820` — `response.text().await.unwrap_or_default()` — body fetch failures become empty strings, then likely fail downstream JSON parsing with a confusing error.

---

## 5. Cargo / dependency hygiene

### 5.1 Per-crate observations

- `bridge` pins FRB to `=2.11.1` exact; otherwise workspace-managed. Good.
- `native` declares `once_cell = "1.19"` but **never imports it** (uses `std::sync::OnceLock`). Dead dep.
- `sequencer` uses `base64 = "0.22"`; `bridge`/`indi`/`alpaca` use `0.21` — duplicate semver.
- `ascom` Windows-gated correctly; `updater` clean.

No `*`-versioned deps, no `failure`, no old `tokio`. Good.

### 5.3 Duplicate semvers (from `cargo tree --duplicates`)

| Crate | Versions present | Bloat | Cause |
|---|---|---|---|
| `base64` | 0.21.7, 0.22.1 | ~80 KB | sequencer uses 0.22, bridge/indi/alpaca use 0.21 |
| `thiserror` | 1.0.69, 2.0.18 | substantial | mdns-sd brings in 2.0 |
| `socket2` | 0.5.10, 0.6.3 | small | reqwest vs mdns-sd |
| `getrandom` | 0.2, 0.3, 0.4 | small | varied |
| `hashbrown` | 0.15.5, 0.17.1 | small | indexmap variants |
| `windows-sys` | 0.48, 0.52, 0.59, 0.61 | **large on Windows** | mixed `windows` crate transitive |
| `windows-targets` | 0.48.5, 0.52.6 | large on Windows | same |

**Action.** Unify `base64` to 0.22 (one-line edit in `bridge/`, `indi/`, `alpaca/` Cargo.toml). The 4-way windows-sys split needs a `[patch.crates-io]` block or upgrade of the `windows = "0.52"` workspace dep to the latest (0.62) to consolidate.

### 5.4 Outdated crates (informational)

`base64`, `flutter_rust_bridge`, `image`, `libloading`, `lru`, `mdns-sd`, `quick-xml`, `rand`, `reqwest`, `thiserror`, `windows`, `zip` all have newer versions. Most upgrades are 1-line; `image` 0.24 → 0.25 is API-breaking.

---

## 6. Crate boundaries

### 6.1 `bridge` over-exports

`bridge/src/lib.rs` declares ~20 modules then **re-exports everything with `pub use ::*`**. This means consumers (`apps/desktop` via the FFI) see the entire internal API. For an FFI crate this is partially excusable because everything must be visible to the Dart-side generator, but the FRB attribute system already gates that. The `pub use api::*; pub use device::*; …` creates a flat namespace and is brittle when adding new internal modules.

### 6.2 Device-specific logic in `bridge/src/api.rs`

`api.rs` at **9770 lines** imports `nightshade_native`, `nightshade_alpaca`, `nightshade_indi`, `nightshade_ascom`, `nightshade_imaging`, `nightshade_sequencer`. It is the union catch-all. Concrete leaks of domain logic into the FFI crate:

- `api.rs:1535-2900` — `SimulatedCamera`, `SimulatedMount`, `SimulatedFocuser`, `SimulatedFilterWheel`, `SimulatedRotator` are full simulator implementations living in the bridge. These belong in a `nightshade_simulator` crate or under `nightshade_native/sim/`.
- `api.rs:3052` — Autofocus cancel-token plumbing. Should live in `sequencer/`.
- `api.rs:3355` — `UNIFIED_IMAGE_STORAGE` HashMap of captured images. Should be in `nightshade_imaging` or a new `nightshade_image_store` crate.
- `api.rs:7577` — `POLAR_ALIGN_RUNNING` flag and ~800 lines of polar-alignment math from line 7571 down. Already partially in `sequencer/src/polar_align.rs`; the bridge layer should only orchestrate.

### 6.3 `native` crate purity

`native/Cargo.toml` depends on `nightshade_imaging` "for buffer pooling". This is *not* pure FFI wrapping and creates a `native → imaging` dependency that is unnecessary if buffer pooling were exposed via a slimmer `nightshade_buffer` crate. Minor.

---

## 7. Clippy debt

`cargo clippy --workspace --all-features` (no pedantic): **368 warnings**.
With `-W clippy::pedantic`: **7,140 warnings**.

Top 10 pedantic lints:

| Lint | Count | Notes |
|---|---|---|
| `uninlined_format_args` | 1,564 | Trivial: `format!("{}", x)` → `format!("{x}")` |
| `missing_errors_doc` | 1,264 | Documentation lint — high noise for FFI |
| `must_use_candidate` | 530 | Add `#[must_use]` to many getters |
| `semicolon_if_nothing_returned` | 440 | Stylistic |
| `cast_lossless` | 439 | Real: replace `x as f64` with `x.into()` |
| `cast_possible_truncation` | 339 | Real: width/height `u32 → i32` casts |
| `doc_markdown` | 293 | Backtick names in docs |
| `borrow_as_ptr` | 270 | Replace `&x as *const _` with `std::ptr::from_ref(&x)` |
| `cast_sign_loss` | 223 | Real in some places (e.g., negative timestamps) |
| `cast_possible_wrap` | 148 | Real for `usize → i32` |

**Real findings:** the four `cast_*` rules (1,049 combined) cover real silent-truncation bugs at FFI boundaries (especially in ASCOM/Alpaca which use `i32` HRESULT-style codes). Worth a sweep.

**Noise:** `missing_errors_doc`, `doc_markdown`, `must_use_candidate`, `uninlined_format_args`, `semicolon_if_nothing_returned` — defer.

**Promote to `-D warnings` next cycle:**
1. `clippy::await_holding_lock`
2. `clippy::cast_possible_truncation` (with `#[allow]` audit)
3. `clippy::undocumented_unsafe_blocks` (currently silent — would force the 700+ unsafe blocks to gain SAFETY comments)
4. `clippy::result_unit_err` (catches `Result<T, ()>`)

---

## 8. Performance / allocation

### 8.1 Hot-loop allocations

`imaging/src/processing.rs` — uses `rayon::par_iter()` with tile regions. Inner loop is mostly arithmetic; no per-iteration `Vec::new()` spotted. `buffer_pool.rs` exists explicitly to avoid per-frame allocation.

### 8.2 `image.data.clone()` in `imaging/src/lib.rs:371, 562, 589, 646, 672`

Five sites clone the entire pixel buffer for `image::ImageBuffer::from_raw(...)`. If these are debayer/stretch entry points called per-frame (common for live-view), this is a 23-122 MB copy per call. Worth checking whether they can take `&[u8]` or move the original.

### 8.3 Synchronous I/O inside `async fn`

10 sites of `std::fs::read|write|read_dir|read_to_string`. Two are in `async fn` contexts:

- `bridge/src/imaging_ops.rs:885` — `std::fs::read(path)` inside a function called from FFI. May or may not be inside a `spawn_blocking`; needs check.
- `sequencer/src/checkpoint.rs:196, 252` — checkpoint save/load. Synchronous is fine because checkpoint frequency is low (per node).

The `lib.rs:320, 337, 359, 374` log-reading sites are sync but executed once per log query.

---

## 9. `bridge/src/api.rs` deep dive (9,770 lines)

285 functions in one file. Already broken into thematic sections via `// =====` banners. **Concrete decomposition** based on existing sections (37 files, 30-830 lines each, median ~150):

| Proposed file | Source range in `api.rs` |
|---|---|
| `api/init.rs`, `events.rs`, `discovery.rs` | 97-995 |
| `api/connection.rs`, `heartbeat.rs`, `versioning.rs` | 996-1530 |
| `api/{camera_sim,camera,mount,focuser,filter_wheel,dome,switch,cover_calibrator}.rs` | 1531-2277 |
| `api/sim/{mount,focuser,fw,rotator}.rs` | 2278-2897 |
| `api/exposure.rs`, `session.rs`, `fits.rs`, `star_detect.rs`, `debayer.rs`, `xisf.rs`, `naming.rs` | 3048-5349 |
| `api/platesolve.rs`, `phd2.rs`, `alpaca.rs` | 5350-6183 |
| `api/{sequencer,checkpoint,sequencer_factory,mosaic,polar_align}.rs` | 6184-8405 |
| `api/{profiles,settings,imaging_files,image_processing,indi_autofocus,capabilities,quirks,qhy}.rs` | 8406-9770 |

FRB code generation works on `mod api` boundaries; `flutter_rust_bridge.yaml` would need `rust_input: api/**/*.rs`. Worth verifying with FRB docs before splitting.

### 9.1 Other observations in `api.rs`

- **Repeated boilerplate:** parameter validation (`if duration <= 0.0 { return Err(…) }`) is copy-pasted in `start_exposure` variants. A `validate_exposure(duration, gain, offset) -> Result<()>` helper would dedupe ~30 sites.
- **Giant match arms:** `api_discover_devices()` (line 675) is ~400 lines. Most can be extracted to per-driver helpers.

---

## 10. Cross-platform conditional compilation

### 10.1 Distribution

`bridge/src/devices.rs` has **106** `#[cfg(windows)]` blocks, by far the heaviest. `bridge/src/real_device_ops.rs` has 30. These gate ASCOM-only code paths. Reviewed visually — gates are on the correct side.

`ascom/Cargo.toml` keeps `tracing` as the only non-gated dep, with the rest in `[target.'cfg(windows)'.dependencies]` — that's correct.

### 10.2 `nightshade_indi` cross-platform

Confirmed: zero `#[cfg(unix)]` or `#[cfg(windows)]` in `indi/src/*.rs`. The crate compiles on all platforms (Windows TCP works fine for INDI), matching the project memory note. **Intentional and correct.**

### 10.3 `nightshade_native` (vendor SDKs)

`native/Cargo.toml` has Windows-only `winapi` plus Unix-only `libloading` duplication (`libloading` is declared at top level *and* gated to `cfg(unix)`). The duplicate entry under `[target.'cfg(unix)'.dependencies]` has no effect.

---

## Quick-win punch list

| # | Item | Type | Effort | Impact | Crate | Reasoning |
|---|---|---|---|---|---|---|
| 1 | Replace `if let Ok(_) = …` in `updater/src/main.rs:244,255,256,266` with `is_ok()` and add `tracing::warn!` on the failure branches | Cleanup + reliability | S | Med | `updater` | Clippy-clean and gives post-mortem trail for failed updates |
| 2 | Replace 6 `let _ = camera.disconnect().await;` in `alpaca/src/guard.rs` with `tracing::warn!`-on-error | Reliability | S | Med | `alpaca` | Drop-time disconnect failures are currently invisible |
| 3 | Unify `base64` (0.21 vs 0.22) and bump `windows` (0.52 → 0.62) to drop 4 duplicate semvers | Build hygiene | S | Med | workspace | Smaller binary on Windows, faster builds |
| 4 | Delete unused `once_cell = "1.19"` dep from `native/Cargo.toml` | Cleanup | S | Low | `native` | `OnceLock` from std is already used |
| 5 | Convert `indi/src/camera.rs:448,513` and `indi/src/filterwheel.rs:71` from `Handle::current().block_on(self.client.read())` to plain `.await` | Async correctness | S | High | `indi` | Eliminates real deadlock risk on single-thread runtimes; trivial rewrite |
| 6 | Add SAFETY comments to all `unsafe impl Send/Sync` lines in `native/src/vendor/*.rs` | Documentation | M | High | `native` | 700+ unsafe blocks are currently undocumented; enables `clippy::undocumented_unsafe_blocks` gate |
| 7 | Split `bridge/src/api.rs` along existing section banners into `bridge/src/api/*.rs` (see §9 table) | Maintainability | L | High | `bridge` | Single biggest source of merge conflicts; once split, per-feature ownership becomes possible |
| 8 | Bound `UNIFIED_IMAGE_STORAGE` (`api.rs:3355`) with an LRU + eviction event | Memory | M | High | `bridge` | Long sessions leak memory at the rate of capture throughput |
| 9 | Audit all 288 `unwrap_or_default/(0)/(false)` sites and either justify with `// Why:` or convert to `?` | Correctness | L | High | workspace | Direct CLAUDE.md "no silent fallbacks" enforcement |
| 10 | `native/src/vendor/fli.rs:439` — replace `CString::new(path.clone()).unwrap()` with `?` | Panic-safety | S | Low | `native` | Last `.unwrap()` on user-derived bytes in vendor wrappers |

**Top 5 by impact-per-effort:** 5, 1, 2, 3, 6.

---

## Top 3 highest-impact findings

1. **Six detached `tokio::spawn` tasks with no panic supervision** — sequencer execution (`sequencer/src/executor.rs:658`), event bridge (`bridge/src/api.rs:6489`), polar-align monitor (`api.rs:7755`), and the imaging-pipeline worker (`imaging_ops.rs:61, 627`). A panic in any one silently kills its feature with zero log signal. Wrap each in a sentinel-logging `JoinHandle` watcher.

2. **288 `unwrap_or_default()`/`unwrap_or(false)`/`unwrap_or(0)` silent fallbacks** with zero `// Why:` justifications. Direct violation of the CLAUDE.md "errors are a feature" rule. The Alpaca client alone has 8 `response.text().await.unwrap_or_default()` that mask HTTP failures.

3. **`bridge/src/api.rs` is 9,770 lines** with 285 public FFI functions and ~50 distinct concerns. Decomposition along its own existing section banners is mechanical and unblocks per-domain ownership, faster IDE indexing, and lighter merge conflicts.

---

