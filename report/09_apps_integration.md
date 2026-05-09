# 9. Apps & Integration Audit

**Rating: B+ (Good with some issues)**

## Scope
- `apps/desktop/` - Desktop app entry, headless mode, platform integration
- `apps/mobile/` - Mobile companion app
- `packages/nightshade_core/lib/src/backend/` - Backend abstraction layer
- `melos.yaml` - Monorepo build system
- `.github/workflows/ci.yml` - CI/CD pipeline
- `scripts/` - Build and deployment scripts

---

## 1. Desktop App (`apps/desktop/`)

### 1.1 Entry Point (`apps/desktop/lib/main.dart`)

**Initialization flow (lines 19-95):**
1. `WidgetsFlutterBinding.ensureInitialized()`
2. Check `--headless` flag or `NIGHTSHADE_HEADLESS` env var
3. Initialize native bridge with log directory
4. Initialize profile storage and settings storage
5. Initialize window manager with custom `WindowOptions`
6. Initialize `CatalogManager`
7. Create `ProviderContainer` with FfiBackend override
8. Check `_shouldStartMinimized` setting from DB
9. Show window, then minimize if setting enabled
10. Start background services (non-blocking via `Future.microtask`)
11. Run `NightshadeApp(isDesktop: true)` via `UncontrolledProviderScope`

**Findings:**

- **BUG: Hardcoded version string** (`main.dart:16`): `const String appVersion = '2.0.0'` is hardcoded but `version.yaml` says `2.5.0`. The `appBuildNumber` is `1` vs `5` in `version.yaml`. The version constant is used in LAN push update receiver (`main.dart:197`), discovery broadcasting (`main.dart:187`), and update push discovery (`main.dart:221`). Stale version means the OTA updater may malfunction or re-apply already-installed updates.

- **BUG: Duplicate headless code paths** (`main.dart:244-416`): The `_runHeadless()` method in `main.dart` duplicates all the same handler wiring as the dedicated `main_headless.dart`. The `main_headless.dart` uses the modern `HeadlessApiServer` (Shelf-based, with auth, request IDs, modular handlers), while the `_runHeadless()` in `main.dart` uses the older `NightshadeWebServer` with manual handler wiring. If the user starts headless via `--headless` flag on the desktop binary, they get the old code path. If they build targeting `main_headless.dart`, they get the modern one. This is confusing and error-prone.

- **BUG: Silent error swallowing in `_startBackgroundServices`** (`main.dart:228-231`): The outer catch swallows all errors with `debugPrint('[MAIN] Web server not available: $e')`. If the web server fails to bind on port 8080 (e.g., another instance running), the user gets no visible indication.

- **Code duplication**: Handler wiring code at `main.dart:98-241` is ~150 lines of procedural handler assignment that is fully duplicated in `_startHeadlessServices()` at lines 296-416. This is a maintenance hazard -- any new handler added to one block must be manually added to the other.

- **Excessive `print()` statements**: Over 40 raw `print()` calls in handler functions (`main.dart:428-1407`). These should use the `LoggingService` for consistency and controllable log levels.

### 1.2 Headless Mode (`apps/desktop/lib/main_headless.dart`)

**Well implemented.** Key features:
- Proper error handling with `try/catch` wrapping the entire startup
- `SIGINT`/`SIGTERM` signal handling (SIGTERM only on Linux/macOS)
- Auth support via `--auth-token`, `--require-auth`, env vars
- UDP discovery server on port 45679
- Local IP detection for display
- Clean `ProviderContainer` lifecycle

**Issues:**

- **BUG: Catalog init silently catches errors** (`main_headless.dart:130-138`): `_initializeCatalogManager()` catches all exceptions and only prints them. If the catalog directory is inaccessible, headless mode starts without catalog support. This is inconsistent with the project CLAUDE.md mandate: "Errors are a feature. Silent fallbacks hide bugs for months."

- **Missing database init error escalation** (`main_headless.dart:179-186`): Database initialization failure is logged as a warning but execution continues. The headless server should NOT continue without a database -- sequences, targets, sessions all depend on it.

- **No profile/settings storage init**: Unlike `main.dart` (lines 38-44), the headless entry point does not call `apiInitProfileStorage()` or `apiInitSettingsStorage()`. This means equipment profiles are unavailable in headless mode.

### 1.3 Headless API Server (`apps/desktop/lib/headless_api_server.dart`)

**Excellent architecture.** Uses Shelf router with modular handler classes:
- 23 handler modules covering all feature areas
- WebSocket `/events` endpoint for real-time event streaming
- Authentication middleware with bearer token support
- Request ID tracking via `x-request-id` header
- CORS support for cross-origin access
- Comprehensive API surface: 120+ endpoints covering devices, camera, mount, focuser, filter wheel, rotator, PHD2 guiding, sequencer, plate solving, profiles, settings, polar alignment, sessions, targets, sequences, flat wizard, mosaic, analytics, weather, suggestions, transients, backup, framing, planetarium, dome, safety monitor, scheduler, focus model

**Issues:**
- The old `NightshadeWebServer` in `main.dart` bypasses all this modern infrastructure. There are essentially two competing server implementations.

### 1.4 Platform Integration

- **Window management**: Uses `window_manager` with hidden title bar, custom size/minimum size
- **Start minimized**: Reads setting from database before provider initialization
- **Background services**: Web server, UDP discovery, LAN push updates, WebRTC signaling -- all started non-blocking
- **No system tray integration**: No system tray icon for minimize-to-tray behavior (would be expected for a long-running astrophotography app)

---

## 2. Mobile App (`apps/mobile/`)

### 2.1 Architecture

The mobile app is a **thin companion client**, not a standalone app. It:
1. Discovers a running desktop/headless Nightshade server on the local network
2. Connects via `NetworkBackend` (HTTP REST + WebSocket)
3. Renders the full `NightshadeApp(isMobile: true)` shared UI
4. Provides mobile-specific services (notifications, battery, wake lock, foreground service)

**Connection flow** (`apps/mobile/lib/main.dart:149-196`):
1. Auto-discovery via `EnhancedNightshadeDiscovery.discoverWithFallback()`
2. Fallback: QR code scanning, manual IP entry
3. Save last server for auto-reconnect on next launch
4. Connection health monitoring (5-second polling)
5. "Skip Connection" mode to view UI without backend

### 2.2 Mobile-Specific Services

**MobileSequenceHooks** (`apps/mobile/lib/services/mobile_sequence_hooks.dart`):
- Listens to `sequenceExecutionStateProvider` and `sequenceProgressProvider`
- Manages foreground service, notifications, power/wake lock
- Auto-pauses sequence on critical battery (<= 10%)
- Sends meridian flip notifications based on progress message string matching

**ForegroundService** (`apps/mobile/lib/services/foreground_service.dart`):
- Android foreground notification for imaging sessions
- Updates notification with exposure progress
- Wake lock integration

**PowerService** (`apps/mobile/lib/services/power_service.dart`):
- Battery monitoring via `battery_plus`
- Wake lock via `wakelock_plus`
- 4-tier warning system: normal > low (20%) > veryLow (15%) > critical (10%)

**NotificationService** (`apps/mobile/lib/services/notification_service.dart`):
- Local notifications via `flutter_local_notifications`
- Android notification channels (sequence, warnings, info)
- iOS permission requests
- Notifications: sequence complete, sequence failed, meridian flip, low disk, low battery

**NetworkService** (`apps/mobile/lib/services/network_service.dart`):
- Connectivity monitoring via `connectivity_plus`
- Auto-reconnect when WiFi regained
- Last-known server persistence

### 2.3 Issues

- **BUG: NativeBridge init on mobile** (`apps/mobile/lib/main.dart:25-33`): The mobile app calls `NativeBridge.init()` which attempts to load the Rust FFI library. On iOS/Android, this will either fail (if the native lib isn't bundled) or waste resources loading a library that won't be used (mobile uses `NetworkBackend`, not `FfiBackend`). The error is caught but represents wasted startup time.

- **BUG: Meridian flip detection via string matching** (`mobile_sequence_hooks.dart:115`): `next.message?.toLowerCase().contains('meridian flip')` is fragile. If the message format changes (e.g., "Performing meridian flip" vs "Meridian Flip in progress"), the notification breaks.

- **BUG: ForegroundService `_isRunning` not set to true** (`foreground_service.dart:62-68`): `startService()` calls `FlutterForegroundTask.startService()` but never sets `_isRunning = true`. The `updateProgress()` method (line 76) checks `if (!_isRunning) return;` and will always bail out. Progress notifications will never update. The `setRunning()` method is only called from `ImagingTaskHandler.onStart()` which runs in an isolate and gets a different singleton instance.

- **Duplicate `NetworkBackend` instantiation** (`apps/mobile/lib/main.dart:229-230`): After calling `ref.read(backendProvider.notifier).connect(...)` which creates a `NetworkBackend` internally, the code immediately creates a second `NetworkBackend` instance to sync location. This creates redundant HTTP clients and connections.

- **Missing `NativeBridge.init()` log directory**: Desktop passes `logDirectory` to `NativeBridge.init()`, but mobile calls it without any arguments. If the init succeeds, logs go to an unspecified location.

---

## 3. Backend Abstraction Layer

### 3.1 Interface (`nightshade_backend.dart`)

**Comprehensive and well-structured.** 598 lines defining:
- Device discovery & connection (6 methods)
- Camera control (10 methods)
- Mount control (7 methods)
- Focuser control (4 methods)
- Filter wheel control (3 methods)
- Rotator control (4 methods)
- PHD2 guiding (15 methods)
- Generic guiding (3 methods)
- Plate solving (1 method)
- Sequencer control (12 methods)
- Checkpoint/recovery (6 methods)
- Equipment status (5 methods)
- Equipment capabilities (5 methods)
- Equipment profiles (5 methods)
- Settings & location (4 methods)
- Image processing (5 methods)
- Polar alignment (2 methods)
- Image download (3 methods)
- Device health (3 methods)
- Lifecycle (`dispose()`)

### 3.2 FfiBackend (`ffi_backend.dart`)

**Implementation quality: A-**

- Wraps all `bridge.NativeBridge` static methods
- Proper dispose lifecycle with `_disposed` flag
- Cached broadcast event stream with proper cleanup
- Rich event type extraction for all bridge event payload types (Equipment, Guiding, Sequencer, Imaging, PolarAlignment)
- Regex fallback for unknown event types

**Issues:**
- Uses `_database` field but only for session image queries -- most operations go directly through FFI. The DB dependency could be made optional more cleanly.

### 3.3 NetworkBackend (`network_backend.dart`)

**Implementation quality: A-**

- HTTP client with connection pooling and keep-alive
- WebSocket for real-time event streaming
- Exponential backoff reconnection (1s, 2s, 4s, 8s, 16s, 30s max)
- Connection state management with stream
- Retryable requests (3 attempts) with transient failure detection
- Structured error parsing from server responses
- Authentication header injection

**Issues:**
- **No request timeout configuration**: All requests use a hardcoded 30-second timeout. Long operations (plate solving, autofocus) may need longer timeouts.
- **WebSocket reconnection runs indefinitely**: No limit on reconnection attempts; could drain battery on mobile.

### 3.4 DisconnectedBackend (`disconnected_backend.dart`)

**Implementation quality: A**

Clean implementation. Every method throws with a clear user-facing message via `_throwNotConnected()`. This is the correct default state for mobile.

---

## 4. Build System

### 4.1 Melos Configuration (`melos.yaml`)

**Well organized.** Scripts grouped into:
- Development commands (`dev`, `dev:norun`, `dev:quick`, `dev:clean`)
- Code quality (`analyze`, `format`, `test`)
- Production builds (desktop: windows/macos/linux, mobile: android/ios)
- Code generation (`generate`)
- SDK copy scripts

**Issues:**
- **macOS build uses `|| true`** (`melos.yaml:80`): `cargo build --release --target x86_64-apple-darwin || cargo build --release --target aarch64-apple-darwin` means if x86 build fails for a real reason (not architecture mismatch), it silently falls through to ARM build. And if ARM also fails, melos treats it as success.
- **Dev scripts are PowerShell-only**: `dev.ps1` means Linux/macOS developers can't use `melos run dev`. The `build_native.sh` exists for Rust-only builds but there's no unified cross-platform dev script.
- **Missing `generate` filter**: `melos run generate` runs `build_runner` in all packages, including those without code generation. This wastes time.

### 4.2 CI/CD (`.github/workflows/ci.yml`)

**Comprehensive pipeline** with 6 jobs:

| Job | Purpose | Quality |
|-----|---------|---------|
| `analyze` | Dart analysis + production gates | Good - includes placeholder audit, fail-closed check, behavioral audit, dependency hygiene |
| `launch-gate` | Duplicate of analyze (zero production warnings) | Redundant - nearly identical to `analyze` job |
| `test-dart` | Flutter tests | Basic but functional |
| `test-rust` | Cargo test + clippy | Good |
| `format-check` | Dart + Rust formatting | Good |
| `build-test` | Matrix build (Ubuntu/Windows/macOS) | Good but has issues |
| `coverage` | LCOV + Codecov upload | Good |

**Issues:**
- **`launch-gate` is nearly identical to `analyze`**: Both run `analyzer_rollup.dart` and `placeholder_audit.dart` with the same flags. This doubles CI time without additional value.
- **macOS Rust build uses `|| true`** (`ci.yml:217`): `cargo build --release --manifest-path bridge/Cargo.toml || true` means the macOS Rust build always "succeeds" even on failure, making the macOS Flutter build test meaningless (it'll run without the native library).
- **No mobile build in CI**: Only desktop platforms are tested. Android/iOS builds are not verified.
- **Codecov with `fail_ci_if_error: false`**: Coverage upload failures are silently ignored.
- **Missing dependency caching**: Dart pub dependencies are not cached (Flutter cache helps but isn't complete).

### 4.3 Build Scripts (`scripts/`)

Eight scripts covering Windows, Linux, macOS, and packaging:
- `dev.ps1` - Main dev workflow (FRB + Rust + copy DLLs + run)
- `build_native.ps1` / `build_native.sh` / `build_native.bat` - Rust-only builds
- `copy_libraw.ps1` / `copy_macos_lib.sh` - DLL/dylib copying
- `package_windows.ps1` - Windows installer packaging
- `build_update_package.ps1` / `publish_update.ps1` - OTA update pipeline

**No Linux/macOS equivalent of `dev.ps1`**, which is the most important script.

---

## 5. Code Sharing & Integration Quality

### 5.1 Desktop/Mobile Code Sharing

**Excellent.** The shared code in `packages/nightshade_app/` provides:
- All screens (dashboard, equipment, imaging, sequencer, planetarium, settings, analytics, framing)
- All widgets (over 40 shared widgets)
- Router configuration
- Location sync service

The `NightshadeApp` widget accepts `isMobile` and `isDesktop` flags for platform-specific behavior:
- Desktop gets `UpdateManagerWidget` wrapper
- Mobile uses default scaling
- Shared theming, routing, and state management

### 5.2 Backend Abstraction Cleanliness

**Very clean.** The `NightshadeBackend` interface properly abstracts all device control. The backend selection is managed by `BackendNotifier`:
- Desktop always uses `FfiBackend`
- Mobile uses `NetworkBackend` when connected, `DisconnectedBackend` when not
- No platform-specific hacks in the business logic layer

### 5.3 Platform-Specific Code

Platform-specific code is well-contained:
- **Desktop only**: Window management, system tray (missing), headless API server, LAN push updates, WebRTC signaling
- **Mobile only**: Foreground service, battery management, wake lock, local notifications, QR scanning, network connectivity monitoring
- **Shared**: Everything in `packages/`

---

## 6. Bugs Summary

| # | Severity | Location | Description |
|---|----------|----------|-------------|
| 1 | **High** | `apps/desktop/lib/main.dart:16` | Hardcoded version `2.0.0` vs `version.yaml` `2.5.0`; breaks OTA update version comparison |
| 2 | **High** | `apps/mobile/lib/services/foreground_service.dart:62-68` | `_isRunning` never set to `true` in `startService()`; progress notifications never update |
| 3 | **Medium** | `apps/desktop/lib/main.dart:244-416` | Duplicate headless code path using outdated `NightshadeWebServer` instead of modern `HeadlessApiServer` |
| 4 | **Medium** | `apps/desktop/lib/main_headless.dart:130-138` | Catalog init error silently caught |
| 5 | **Medium** | `apps/desktop/lib/main_headless.dart:179-186` | Database init failure treated as warning, server continues without DB |
| 6 | **Medium** | `apps/desktop/lib/main_headless.dart` | Missing `apiInitProfileStorage` and `apiInitSettingsStorage` calls |
| 7 | **Medium** | `apps/mobile/lib/main.dart:25-33` | Unnecessary `NativeBridge.init()` on mobile (waste / potential crash) |
| 8 | **Low** | `apps/mobile/lib/services/mobile_sequence_hooks.dart:115` | Meridian flip detection via fragile string matching |
| 9 | **Low** | `apps/desktop/lib/main.dart:228-231` | Web server startup errors silently swallowed |
| 10 | **Low** | `apps/mobile/lib/main.dart:229-230` | Duplicate `NetworkBackend` instantiation for location sync |
| 11 | **Low** | `.github/workflows/ci.yml:217` | macOS Rust build `|| true` masks real failures |
| 12 | **Low** | `melos.yaml:80` | macOS build fallback logic hides errors |

---

## 7. Missing Pieces

1. **System tray integration**: No minimize-to-tray for the desktop app. Important for an app that runs all night during imaging sessions.
2. **Cross-platform dev script**: No Linux/macOS equivalent of `dev.ps1`. Linux developers must manually chain commands.
3. **Mobile build CI**: Android and iOS builds are not tested in CI.
4. **Version automation**: Version is hardcoded in `main.dart` instead of being read from `version.yaml` at build time.
5. **Graceful shutdown on desktop GUI**: No equivalent of the headless mode's SIGINT handler for the GUI app. Closing the window during an active sequence may not checkpoint properly.
6. **Connection recovery on mobile**: If the server restarts, the mobile app's `NetworkBackend` WebSocket reconnects, but `BackendNotifier` state may not properly re-sync device/sequence state.
7. **Rate limiting on headless API**: No rate limiting or request throttling on the headless API server. Malicious or buggy clients could overload the server.
8. **HTTPS support**: All API communication is plain HTTP. On a local network this is acceptable, but credentials/tokens are transmitted in cleartext.

---

## 8. Recommendations

### P0 (Fix immediately)
1. Fix hardcoded version in `main.dart` -- either read from `version.yaml` at build time or maintain a single `const` that build scripts update
2. Fix `_isRunning` bug in `ImagingForegroundService.startService()` -- add `_isRunning = true` after successful service start

### P1 (Fix soon)
3. Remove the duplicate `_runHeadless()` / `_startHeadlessServices()` from `main.dart`. When `--headless` flag is detected, delegate to the modern `main_headless.dart` entry point's logic
4. Add profile/settings storage initialization to `main_headless.dart`
5. Remove `NativeBridge.init()` from mobile app (or guard with platform check -- only init on desktop)
6. Escalate database init failure in headless mode to a fatal error

### P2 (Improve)
7. Replace string-matching meridian flip detection with a proper event type
8. Add system tray support for desktop
9. Create a cross-platform dev script (bash version of `dev.ps1`)
10. Fix macOS CI build to not use `|| true`
11. Add mobile builds to CI pipeline
12. Replace raw `print()` calls in `main.dart` handlers with `LoggingService`
