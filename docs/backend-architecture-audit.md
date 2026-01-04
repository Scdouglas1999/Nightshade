# Nightshade Backend Architecture Audit (Dart + Rust + Network)

### Scope & intent
- **Goal**: Review the backend architecture that powers Nightshade’s UI workflows for **efficiency, correctness, maintainability, and structure**.
- **In scope**:
  - Dart: `nightshade_core` backend abstraction (`NightshadeBackend`) + implementations (`FfiBackend`, `NetworkBackend`, `DisconnectedBackend`), plus core `services/` and `providers/` that orchestrate device ops.
  - Rust: `native/nightshade_native` bridge layer (FRB API), device manager, driver modules (ASCOM/Alpaca/INDI/Native), sequencer device ops.
  - Network: REST/WS API surface + client implementation and parity considerations.
- **Out of scope**: UI-level UX polish (unless it causes backend inefficiency), feature design debates, and code changes.

### Audit methodology
- Identify hot paths (events, image transfer, sequencing loops, device polling) and check for avoidable overhead.
- Review API boundaries (who owns “truth” for device state/settings, where conversions happen, and whether they’re duplicated).
- Check parity and drift between:
  - `NightshadeBackend` contract ↔ `FfiBackend` ↔ `NetworkBackend`
  - Dart models ↔ Rust models (FRB) ↔ network JSON
- Note structural risks (mega-files, circular dependencies, “leaky abstraction” spots, testability).

---

## Findings (in progress)

### 1) Backend layer overview (Dart)
#### `nightshade_backend.dart` is overloaded and “leaks” implementation concerns
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` mixes:
  - **Core protocol types** (`DeviceType`, `DriverType`, `NightshadeEvent`, etc.)
  - **DTO/models** (e.g., `DeviceInfo`, `CapturedImageResult`, `PlateSolveResult`, `SequencerStatus`, `CheckpointInfo`, …)
  - The actual **`abstract class NightshadeBackend` contract**
- Several types appear duplicated/parallel to other models in `src/models/**` (example: `PlateSolveResult` exists both here and in `src/services/plate_solve_service.dart`’s surface; imaging models exist in `src/models/imaging/`).
- The contract also references FRB-generated types directly:
  - `bridge_api.FitsWriteHeader`
  - `bridge_api.AutofocusResultApi`
  - (and other `nightshade_bridge` API types)
- This makes the “backend abstraction” less abstract:
  - It binds `NightshadeBackend` to the FRB package even in `NetworkBackend` and `DisconnectedBackend`.
  - It encourages UI/services to depend on bridge DTOs rather than stable, backend-agnostic models.

Sources:
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart`
- `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (imports `nightshade_bridge` and uses bridge types heavily)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (imports `nightshade_bridge/src/api.dart` as `bridge_api`)

Maintainability note:
- Several backend-layer files have “mega-file” scale:
  - `nightshade_backend.dart`: ~741 LOC
  - `ffi_backend.dart`: ~1612 LOC
  - `network_backend.dart`: ~1627 LOC

These aren’t automatically “bad”, but in this case they correlate with type duplication, drift, and cross-layer imports.

#### Settings model drift is visible at the backend boundary (type collisions + unclear ownership)
- `nightshade_backend.dart` imports both:
  - `src/models/settings/app_settings.dart` as `models`
  - `src/providers/settings_provider.dart` (with `hide AppSettings`)
- That’s a strong smell that “settings” are not cleanly separated between:
  - Client/UI preferences
  - Server/runtime configuration
  - Backend-owned state

Source:
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (imports)

#### `NetworkBackend` creates a new `HttpClient` per request (avoidably inefficient)
- `_get()`/`_post()`/etc instantiate `HttpClient()` inside each call and close it at the end.
- This prevents connection pooling/keep-alives and adds overhead on high-frequency paths (status polling, sequencer progress, etc.).
- Prefer a long-lived `HttpClient` (or `package:http` client) owned by `NetworkBackend` with:
  - keep-alive enabled
  - shared headers/auth
  - consistent timeouts
  - centralized JSON decoding/error mapping

Source:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`_get`, `_post`, `HttpClient()` usage)

#### `NetworkBackend._retryableRequest` uses `e as Exception` (can throw and mask root cause)
- In `catch (e)`, it assigns `lastException = e as Exception;`.
- If a non-`Exception` (e.g., an `Error`) bubbles up, this cast can throw and obscure the original failure.

Source:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`_retryableRequest`)

#### `DisconnectedBackend` is clear but verbose (maintenance burden)
- `DisconnectedBackend` implements every method by calling `_throwNotConnected()`, duplicating the entire interface.
- This is correct behaviorally, but it’s brittle: any backend API expansion forces large boilerplate updates.
- Consider a pattern that centralizes “not connected” behavior (e.g., abstract base class with default throws, or codegen).

Source:
- `packages/nightshade_core/lib/src/backend/disconnected_backend.dart`

#### Backend lifecycle management doesn’t dispose old backends (resource leak risk)
- `BackendNotifier.connect()` replaces the backend state with a new `NetworkBackend`, and `disconnect()` replaces it with `DisconnectedBackend`.
- `NetworkBackend` holds:
  - an open WebSocket channel,
  - stream controllers,
  - a reconnect timer.
- There is no code in `BackendNotifier` that calls `NetworkBackend.dispose()` (or `disconnect()`) when switching away, so stale connections/timers may linger until GC.
- This is both an efficiency issue (extra sockets/timers) and a correctness issue (duplicate event streams).

Source:
- `packages/nightshade_core/lib/src/providers/backend_provider.dart` (`BackendNotifier`)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`dispose`, timers, controllers)

#### Structured errors exist (Rust/FRB), but Dart core largely treats errors as strings
- The Rust bridge defines a comprehensive `NightshadeError` enum with rich variants (timeouts, not-supported, driver-specific errors, etc.).
- FRB generates a corresponding Dart `NightshadeError` union type in `nightshade_bridge`.
- In `nightshade_core`, many call sites catch generic exceptions and then:
  - display `e.toString()`, or
  - heuristically classify by message text (e.g., `DeviceError.fromException` in equipment models).
- This loses structured recovery intent (e.g., “not supported” vs “temporary comms failure”) and forces UI/services into broad “try/catch” behavior.

Sources:
- `native/nightshade_native/bridge/src/error.rs` (`NightshadeError`)
- `packages/nightshade_bridge/lib/src/error.freezed.dart` (generated Dart `NightshadeError`)
- `packages/nightshade_core/lib/src/models/equipment/equipment_models.dart` (`DeviceError.fromException`)

### 2) Core orchestration layer (Dart services/providers)
#### `DeviceService` duplicates core enums/models and compensates for inconsistent backend schemas
- `DeviceService` defines its own:
  - `NightshadeDeviceType` enum (overlaps `backend/nightshade_backend.dart`’s `DeviceType`)
  - `DriverBackend` enum (overlaps `backend/nightshade_backend.dart`’s `DriverType`)
  - `AvailableDevice` DTO (overlaps `DeviceInfo` and the unified discovery models)
- Temperature polling pulls `getCameraStatus()` as `dynamic` and then uses heuristic “try multiple field names” extraction to find temperature/power/setpoint.
- This indicates the underlying status payloads are not consistent across backends, so the service is forced to be defensive and “guessy”.

Efficiency/maintainability impact:
- Duplicate types increase cognitive load and migration risk.
- `dynamic` + heuristic extraction is brittle and hard to test; it also obscures which backend is responsible for shaping status correctly.

Source:
- `packages/nightshade_core/lib/src/services/device_service.dart` (type definitions + `_pollCameraTemperature` + `_extract*` helpers)

#### Polling strategy is mostly “fixed interval” rather than event-driven
- `DeviceService` polls camera temperature every 5 seconds via `Timer.periodic`, even though the system already has an event stream concept.
- In remote mode this becomes repetitive HTTP traffic; in local mode it’s unnecessary overhead if the native side can emit temperature changes.

Source:
- `packages/nightshade_core/lib/src/services/device_service.dart` (`_startTemperaturePolling`)

#### Imaging pipeline does expensive data copies and round-trips (largest efficiency hotspot found so far)
- `ImagingService.captureImage()`:
  - Receives `CapturedImageResult.displayData` as a `List<int>` and immediately copies it into a `Uint8List`.
  - Saves FITS by calling:
    1) `backend.getLastRawImageData()` (Rust → Dart transfer of full u16 frame, as `List<int>`)
    2) `backend.saveFitsFile(data: rawData, ...)` (Dart → Rust transfer of the same frame again)
- In `FfiBackend`, both steps go through FRB APIs:
  - `apiGetLastRawImageData()` returns the full frame to Dart.
  - `apiSaveFitsFile(... data ...)` sends it back to Rust for writing.
- In `NetworkBackend`, this is even more expensive:
  - `getLastRawImageData` fetches a binary payload (`/api/imaging/raw-data`) → good.
  - but `saveFitsFile` POSTs JSON containing `'data': data` (a massive integer array) → extremely inefficient over the network.

Why this matters:
- This path is on the critical “every exposure” hot loop.
- It can dominate CPU time, allocations, and bandwidth, and it increases latency for saving/metadata.

Sources:
- `packages/nightshade_core/lib/src/services/imaging_service.dart` (`_saveFitsFile` calls)
- `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (`getLastRawImageData`, `saveFitsFile`)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`getLastRawImageData`, `saveFitsFile`)

Related correctness note:
- The API surface is *per-camera* (`cameraGetLastImage(String deviceId)`), but both local and server implementations behave like a *global last image*:
  - `FfiBackend.cameraGetLastImage(deviceId)` calls `NativeBridge.getLastImage()` without using `deviceId`.
  - The desktop web server’s `/api/camera/last-image` handler calls `NativeBridge.getLastImage()` as well.
- This becomes problematic if you ever support multiple concurrent cameras/exposures.

Sources:
- `packages/nightshade_core/lib/src/backend/ffi_backend.dart` (`cameraGetLastImage`)
- `apps/desktop/lib/main.dart` (`_cameraGetLastImageHandler`)

#### Exposure progress handling uses both event listening and time-based busy waiting
- `ImagingService.captureImage()` subscribes to `backend.eventStream` for progress events, but still uses a `while (...) { Future.delayed(100ms) }` loop based on wall-clock exposure duration.
- This burns CPU and doesn’t truly wait for device completion (slow readout/download can exceed the assumed duration).
- A cleaner approach is: await an “exposure completed” signal (event-driven) with a timeout derived from exposure + margin.

Source:
- `packages/nightshade_core/lib/src/services/imaging_service.dart` (`captureImage` wait loop)

### 3) Rust bridge/device manager layout
#### The bridge `src/` structure is generally sensible and already contains key building blocks
- `native/nightshade_native/bridge/src/` is split into focused modules:
  - driver wrappers (`ascom_wrapper_*.rs`, alpaca/indi code elsewhere)
  - orchestration (`devices.rs` device manager)
  - event/types (`event.rs`, `events.rs`)
  - safety/timeouts (`timeout_ops.rs`, `adaptive_polling.rs`, `device_guard.rs`)
  - ops abstraction (`unified_device_ops.rs`, `real_device_ops.rs`, `sequencer_ops.rs`)
  - and importantly: **capability reporting** (`device_capabilities.rs`)

Source:
- `native/nightshade_native/bridge/src/` (module layout)

Maintainability note:
- Two central Rust bridge files are very large:
  - `bridge/src/api.rs`: ~7253 LOC
  - `bridge/src/devices.rs`: ~6440 LOC

This makes it harder to keep APIs consistent, to test, and to refactor safely. Splitting these by domain (equipment/imaging/sequencer/settings/network) would pay off quickly.

#### Capabilities are well-modeled in Rust, but not surfaced through Dart/network (missed leverage)
- `device_capabilities.rs` defines rich capability structs (camera/mount/focuser/filterwheel/rotator/dome/weather/safety/switch/cover-calibrator), including:
  - boolean “can_*” flags
  - ranges (gain/offset min/max, max binning, exposure min/max)
  - supported enumerations (tracking rates)
- FRB exports `api_get_device_capabilities` and per-device helpers (`api_get_camera_capabilities`, `api_get_mount_capabilities`, etc.) via `bridge/src/api.rs`.
- However, the Dart `NightshadeBackend` contract and `NetworkBackend` do not expose these capability queries, and the web server API has no `/api/*capabilities*` endpoints.
- Practical impact:
  - UI/services are forced into “optimistic call + catch errors” behavior.
  - Capability-driven UI gating and parameter-range validation (which you already need for driver-agnosticism) can’t be implemented cleanly across backends.

Sources:
- `native/nightshade_native/bridge/src/device_capabilities.rs`
- `native/nightshade_native/bridge/src/api.rs` (`api_get_*_capabilities`)
- `packages/nightshade_core/lib/src/backend/nightshade_backend.dart` (no capability API)
- `packages/nightshade_webrtc/lib/src/web_server.dart` (no capability endpoints)

#### Imaging uses a single global “last image” storage that clones buffers (performance + multi-camera correctness risk)
- Rust stores the most recent capture in a global “unified image storage” that contains:
  - display-ready image (`CapturedImageResult`)
  - raw u16 image buffer (`RawImageInfo`)
- `api_get_last_raw_image_data()` returns `Vec<u16>` by cloning the stored raw buffer.
- `api_get_last_image()` returns the display data by cloning the stored display buffer.
- This design has two problems:
  - **Performance**: repeated full-frame clones (store clone + return clone + Dart copies) on the hottest path.
  - **Correctness**: the storage is global, not per-camera; concurrent captures from multiple cameras can overwrite each other. There’s already a comment in `sequencer_ops.rs` noting this race and working around it by routing through `UnifiedDeviceOps` to return image data directly.

Sources:
- `native/nightshade_native/bridge/src/api.rs` (`api_get_last_image`, `api_get_last_raw_image_data`, `store_captured_image_atomically`)
- `native/nightshade_native/bridge/src/sequencer_ops.rs` (comment about `LAST_RAW_IMAGE_INFO` race)

#### `adaptive_polling.rs` is a good idea but currently unused (missed perf improvement)
- The bridge includes an `AdaptivePoller` utility with presets for exposure/slew/idle/download, explicitly designed to avoid fixed-interval polling.
- A repo-wide search suggests it isn’t currently used by the bridge’s long-running operations.
- This is a missed opportunity to reduce status-check overhead and smooth UI progress updates without constant polling.

Source:
- `native/nightshade_native/bridge/src/adaptive_polling.rs` (no other usage found)

#### There are multiple `DeviceOps` implementations (risk of drift / duplicate logic)
- The bridge contains several implementations of the sequencer’s `DeviceOps` trait:
  - `BridgeDeviceOps` (`sequencer_ops.rs`) which calls the exported `api_*` functions
  - `UnifiedDeviceOps` (`unified_device_ops.rs`) which routes through `get_device_manager()` and publishes events
  - `RealDeviceOps` (`real_device_ops.rs`) which directly manages driver access, caching, and movement tracking
- The code comments indicate an ongoing consolidation effort, but as-is there are multiple competing entry points with overlapping responsibilities.
- Recommendation directionally: pick one “blessed” path (likely `UnifiedDeviceOps` + `DeviceManager`) and make other implementations thin adapters or remove them once parity is reached.

Sources:
- `native/nightshade_native/bridge/src/sequencer_ops.rs`
- `native/nightshade_native/bridge/src/unified_device_ops.rs`
- `native/nightshade_native/bridge/src/real_device_ops.rs`

### 4) Network API + client efficiency/parity
#### There are two server implementations with different completeness levels
- **Desktop GUI mode** starts `NightshadeWebServer` (custom `HttpServer` implementation) and wires dozens of handler callbacks from `apps/desktop/lib/main.dart`.
- **Headless mode** starts `HeadlessApiServer` (Shelf + shelf_router) from `apps/desktop/lib/main_headless.dart`.
- `HeadlessApiServer` currently exposes a very small subset of endpoints (devices + basic sequencer), while `NetworkBackend` expects a much wider surface (`/api/equipment/*`, `/api/phd2/*`, `/api/plate-solve`, `/api/settings`, `/api/polar-alignment/*`, `/api/images/*`, etc.).
- Risk:
  - Remote control behavior will differ drastically between desktop vs headless builds.
  - API parity and client compatibility become hard to reason about and test.

Sources:
- `apps/desktop/lib/main.dart` (starts `NightshadeWebServer` and registers handlers)
- `packages/nightshade_webrtc/lib/src/web_server.dart` (implements `/api/*` endpoints)
- `apps/desktop/lib/main_headless.dart` (starts `HeadlessApiServer`)
- `apps/desktop/lib/headless_api_server.dart` (limited endpoints)
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (client expectations)

Maintainability note:
- The desktop GUI “web server” code is also a mega-file:
  - `packages/nightshade_webrtc/lib/src/web_server.dart`: ~2365 LOC
  - `apps/desktop/lib/main.dart`: ~1384 LOC (also contains a large chunk of API handler wiring)

#### WebSocket event streaming is present but not actually wired (push updates likely missing)
- `NetworkBackend` connects to `ws://<host>:<port>/events` and expects each message to decode to a `NightshadeEvent` with fields including `severity`, `category`, `eventType`, `data`, `timestamp`.
- `NightshadeWebServer` supports WebSocket upgrades at both `/api/ws` **and** `/events` “for NetworkBackend compatibility”, but:
  - It does not broadcast backend events anywhere (`broadcastMessage()` exists but is unused).
  - `apps/desktop/lib/main.dart` does not subscribe to `backend.eventStream` and forward events into the web server.
- `HeadlessApiServer` also has a WebSocket and a `broadcastEvent()` helper, but does not subscribe to backend events either, and its event schema (`type` vs `eventType`, missing `severity`) does not match `NetworkBackend._eventFromJson`.
- Net effect: remote clients likely fall back to polling and miss real-time updates (less efficient and can cause UX inconsistencies).

Sources:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`connect()`, `_eventFromJson`)
- `packages/nightshade_webrtc/lib/src/web_server.dart` (WebSocket upgrade + unused `broadcastMessage`)
- `apps/desktop/lib/main.dart` (no event forwarding)
- `apps/desktop/lib/headless_api_server.dart` (WebSocket + incompatible `broadcastEvent` schema)

#### The server’s API routing is “giant if-chain + dozens of nullable handlers”
- `NightshadeWebServer` is effectively a manual router with many request branches and a large set of `typedef` handler fields.
- This works, but it’s difficult to maintain:
  - Adding endpoints requires editing a massive file with many responsibilities (routing, serialization, static file serving, WebSocket, CORS).
  - Many handlers are nullable; failures can become “endpoint returns 501/500” depending on wiring rather than compile-time guarantees.
- Consider consolidating on one approach (e.g., Shelf for both desktop+headless, or a shared routing layer) and enforcing a single API schema.

Source:
- `packages/nightshade_webrtc/lib/src/web_server.dart`

#### Desktop server handlers are tightly coupled to FRB/FFI (`bridge.NativeBridge`) instead of `NightshadeBackend`
- In desktop GUI mode, the `/api/*` handlers wired in `apps/desktop/lib/main.dart` call `bridge.NativeBridge.*` directly (FFI).
- Meanwhile the UI itself is structured around `NightshadeBackend` (`backendProvider`), and headless mode’s `HeadlessApiServer` also uses `backendProvider`.
- Impact:
  - Two separate “backend entry points” exist (backend abstraction vs direct bridge calls).
  - This increases drift risk (one path adds capabilities or fixes a bug; the other path stays stale).
  - It makes it harder to test the API layer against alternate backend implementations or mocks.

Source:
- `apps/desktop/lib/main.dart` (API handlers call `bridge.NativeBridge`)

#### API drift: `NetworkBackend` implements endpoints that the server does not provide
- `NetworkBackend.getLastRawImageData()` calls `GET /api/imaging/raw-data`.
- `NetworkBackend.saveFitsFile()` calls `POST /api/imaging/save-fits` and serializes raw pixel data as JSON.
- No server implementation in the repo exposes `/api/imaging/*` (search matches only the client).
- Impact:
  - These `NightshadeBackend` methods cannot work in remote mode as written.
  - The current “save FITS over network by JSON array” approach would be prohibitively slow even if implemented.

Sources:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`getLastRawImageData`, `saveFitsFile`)
- `packages/nightshade_webrtc/lib/src/web_server.dart` (implemented endpoints; no `/api/imaging/*`)
- repo-wide search for `/api/imaging/*` (matches only the client)

#### Image transfer over the network is JSON-based and will not scale to real camera resolutions
- `NightshadeWebServer`’s `GET /api/camera/last-image` returns JSON containing the image object, which includes `displayData` as a list of integers.
- Even for modest preview frames, JSON encoding/decoding pixel arrays is extremely slow and creates large payloads (and can easily blow memory on mobile clients).
- A more efficient shape is:
  - `GET /api/camera/last-image.jpg` (or `/thumbnail`) returning JPEG bytes (`image/jpeg`)
  - optional `GET /api/camera/last-image.fits` or server-side “save to path” semantics for full-fidelity data
  - keep JSON responses for metadata only (width/height/stats/timestamp), not pixels.

Source:
- `packages/nightshade_webrtc/lib/src/web_server.dart` (`/api/camera/last-image` implementation)

#### Auth/security is effectively “open LAN” today (important to acknowledge)
- `NetworkBackend` has an `authToken` field and adds a `Bearer` header to HTTP requests when present.
- The desktop web server (`NightshadeWebServer`) does not appear to validate any auth header, and sets permissive CORS (`Access-Control-Allow-Origin: *`).
- If this server is run on an untrusted network, it is discoverable and remotely controllable.
- Even if you keep it LAN-only, introducing a minimal auth layer would also improve backend ergonomics (fewer accidental cross-talk issues when multiple clients exist).

Sources:
- `packages/nightshade_core/lib/src/backend/network_backend.dart` (`authToken`, `_addAuthHeaders`)
- `packages/nightshade_webrtc/lib/src/web_server.dart` (CORS + no auth checks)

---

## Recommendations / roadmap (to be filled)
### P0 (highest impact: correctness + performance)
- **Eliminate raw image “ping-pong” for FITS writing**
  - Add a backend API that writes FITS directly from the native-side stored buffer (or from the exposure result) without returning pixels to Dart first.
  - For remote: prefer “save on server” semantics; the client should not POST raw pixels back to the server.
  - Replace any JSON-based pixel transfer with binary streaming endpoints where unavoidable.
- **Make WebSocket events real and schema-stable**
  - Define a single wire schema for `NightshadeEvent` over WS (fields + types) and enforce it in both desktop + headless servers.
  - Subscribe to the server-side backend event stream and forward events to all WS clients.
  - Once events are real, reduce high-frequency polling on the client (temperature/progress/status).
- **Expose device capabilities through the Dart backend**
  - Add capability query methods to `NightshadeBackend` and implement them in both `FfiBackend` (FRB calls already exist) and `NetworkBackend` (add API endpoints).
  - Then, refactor UI/services to validate parameters against capability ranges instead of relying on exceptions.

### P1 (architecture cleanup that reduces drift)
- **Refactor `nightshade_backend.dart` into a clean contract + shared models**
  - Move DTOs/enums out of `nightshade_backend.dart` into `src/models/**`.
  - Remove provider imports from backend contract (`settings_provider.dart` shouldn’t be referenced at this layer).
  - Avoid bridge/FRB types in the `NightshadeBackend` interface. Prefer backend-agnostic models that can be:
    - mapped from FRB types in `FfiBackend`
    - serialized over network in `NetworkBackend`
- **Fix backend lifecycle / disposal**
  - Ensure switching `backendProvider` tears down the previous backend (close WS/timers/streams).
- **Unify and preserve structured errors**
  - Treat FRB `NightshadeError` as first-class on the Dart side (map it into typed `DeviceError` rather than `toString()`).
  - For network calls, return structured error payloads (kind + fields) instead of “string message only”.

### P2 (maintainability + scalability)
- **Decompose mega-files**
  - Split Rust `bridge/src/api.rs` and `bridge/src/devices.rs` into domain modules.
  - Split `NightshadeWebServer` into routing/serialization/static-files/websocket modules (or migrate to a shared Shelf server so headless + desktop share most code).
  - Move desktop API handler functions out of `apps/desktop/lib/main.dart` into a dedicated server module.
- **Consolidate the sequencer `DeviceOps` implementations**
  - Choose a single “official” ops implementation (`UnifiedDeviceOps` + `DeviceManager` is directionally the cleanest) and delete/trim the others after parity.
- **Use typed “status” models everywhere**
  - Replace `dynamic` status payloads with typed models with explicit JSON/FRB mappings (camera/mount/focuser/etc).
  - This reduces brittle “try multiple field names” parsing and enables strict testing.
- **Replace busy-wait loops with event/completer semantics**
  - Imaging exposure completion should await a completion signal (event) with timeouts, not a 100ms spin-loop.
- **Adopt (or generate) a canonical API specification**
  - An OpenAPI schema for `/api/*` would prevent drift between server, `NetworkBackend`, and docs.

### P3 (security + multi-client robustness)
- **Auth + session management**
  - If you expect any use beyond a trusted LAN, add authentication and optional TLS.
  - Even on LAN: a minimal shared-secret token reduces accidental cross-talk and improves debugging in multi-client scenarios.

---

## Suggested implementation order (practical)
1) Save FITS server-side / locally without raw pixel roundtrip (largest perf win, easiest to measure).
2) Wire WS event forwarding + stabilize event schema (improves UX and reduces polling).
3) Capability endpoints + Dart integration (unblocks proper gating/validation across drivers).
4) Contract/model refactor + typed status models (reduces long-term drift).
5) Consolidate servers + split mega-files (maintainability payoff).

