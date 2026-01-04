# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Specific notes for implementations

You are not to EVER use stubs or placeholders to save time or come back to later. Any instances in which you think a stub or placeholder is appropriate, stop and do the full, real implementation of whatever it is you are working on. It is common for you to write up a stub or placeholder, forget about it, and never come back to finish the implementation, therefore it is imperitive that you simply never write stubs or placeholders. 

## Project Overview

Nightshade 2.0 is a cross-platform astrophotography suite built with Flutter (Dart) and Rust. It provides imaging sequencing, device control, and sky visualization for Windows, macOS, Linux desktops, and iOS/Android mobile platforms.

**Current Version:** 2.0.0 (see `version.yaml` for single source of truth)

## Build Commands

The project uses **Melos** for monorepo management. All commands run from the repository root:

```bash
# Bootstrap workspace (install dependencies, generate code)
melos bootstrap

# Code quality
melos run analyze    # Run dart analyze in all packages
melos run format     # Format all packages

# Testing
melos run test       # Run flutter test in all packages

# Rust testing and linting
cd native/nightshade_native
cargo test --all-features
cargo clippy --all-features -- -D warnings

# Code generation (freezed, json_serializable, drift, FFI bindings)
melos run generate

# Build desktop releases (builds Rust + Flutter)
melos run build:desktop:windows
melos run build:desktop:macos
melos run build:desktop:linux

# Build mobile
melos run build:mobile:android
melos run build:mobile:ios
melos run build:mobile:ios:simulator  # iOS simulator (no signing required)

# Run mobile
melos run run:mobile:ios              # Run iOS on device/simulator

# Clean
melos run clean
```

### Development Workflow (Recommended)

Use the unified dev script to avoid hash mismatches between Dart and Rust:

```powershell
# Full rebuild: regenerate FRB bindings + build Rust + copy DLLs + run Flutter
melos run dev

# Quick rebuild (skip FRB if only implementation changed, not API)
melos run dev:quick

# Rebuild without running
melos run dev:norun

# Clean everything and rebuild from scratch
melos run dev:clean
```

**Important:** Don't use `flutter run` directly after changing Rust code - use `melos run dev` instead.

### Pushing Updates to Imaging Laptop

The user has a separate Windows imaging laptop (IP: `192.168.1.59`) for testing. SSH is configured for passwordless access. **Use this workflow when the user asks to push/deploy/test on the imaging laptop:**

```bash
# 1. Build the app (if not already built)
cd apps/desktop && flutter build windows --release

# 2. Copy Rust DLL to build output (if Rust was rebuilt)
cp native/nightshade_native/target/release/nightshade_bridge.dll apps/desktop/build/windows/x64/runner/Release/

# 3. Push ALL files to imaging laptop via SCP
scp -r apps/desktop/build/windows/x64/runner/Release/* scdou@192.168.1.59:"C:/Program Files/Nightshade/"

# 4. Verify the transfer
ssh scdou@192.168.1.59 "dir \"C:\Program Files\Nightshade\data\app.so\""
```

**One-liner for quick pushes (after building):**
```bash
scp -r apps/desktop/build/windows/x64/runner/Release/* scdou@192.168.1.59:"C:/Program Files/Nightshade/"
```

**Full rebuild and push:**
```bash
cd apps/desktop && flutter build windows --release && cp ../../native/nightshade_native/target/release/nightshade_bridge.dll build/windows/x64/runner/Release/ && scp -r build/windows/x64/runner/Release/* scdou@192.168.1.59:"C:/Program Files/Nightshade/"
```

**IMPORTANT NOTES:**
- The user must close Nightshade on the imaging laptop before pushing
- Nightshade is installed at `C:\Program Files\Nightshade` on the imaging laptop
- SSH key auth is configured - no password needed
- Do NOT use Windows file sharing (UNC paths like `\\192.168.1.59\...`) - bash mangles them
- The `data/` folder structure must be preserved (contains `app.so`, `icudtl.dat`, `flutter_assets/`)

### Platform-Specific Build Scripts

Located in `scripts/`:

| Script | Platform | Purpose |
|--------|----------|---------|
| `dev.ps1` | Windows | Main dev build (FRB + Rust + copy DLLs + run) |
| `build_native.ps1` | Windows | Rust build only |
| `build_native.sh` | Linux/macOS | Rust build (auto-detects architecture) |
| `build_native.bat` | Windows | Batch alternative to PowerShell |
| `copy_libraw.ps1` | Windows | Copy LibRaw DLL dependencies |
| `copy_macos_lib.sh` | macOS | Copy dylib to app bundle |
| `package_windows.ps1` | Windows | Full release packaging with installer |
| `build_update_package.ps1` | Windows | Create OTA update packages |
| `publish_update.ps1` | Windows | Publish updates to distribution server |

### Running the Desktop App

```bash
# Preferred method (handles all build steps):
melos run dev

# Direct method (only use if you know DLLs are in sync):
cd apps/desktop
flutter run -d windows  # or macos, linux
```

Headless mode: `--headless` flag or `NIGHTSHADE_HEADLESS=1` environment variable.

## Architecture

### Monorepo Structure

```
apps/
├── desktop/              # Flutter Windows/macOS/Linux app
└── mobile/               # Flutter iOS/Android companion app

packages/
├── nightshade_app/       # Shared UI shell, screens, routing
├── nightshade_core/      # Business logic, database, providers, services
├── nightshade_bridge/    # Dart FFI bindings to Rust (flutter_rust_bridge)
├── nightshade_ui/        # Design system & shared widgets
├── nightshade_planetarium/  # GPU-rendered sky visualization
├── nightshade_plugins/   # Plugin host & API
├── nightshade_screens/   # Shared screen stubs (transitional)
├── nightshade_updater/   # OTA update system with LAN push
└── nightshade_webrtc/    # P2P remote control (WebRTC)

native/nightshade_native/
├── bridge/       # FFI entry point (cdylib + staticlib)
├── sequencer/    # Behavior tree automation engine
├── ascom/        # Windows COM ASCOM drivers
├── indi/         # Linux/macOS INDI protocol
├── alpaca/       # ASCOM Alpaca HTTP protocol
├── imaging/      # Image processing (LibRaw FFI, FITS, XISF)
├── native/       # Vendor SDK FFI bindings (12 vendors)
└── updater/      # Standalone update binary

tools/
└── update_server/  # Local update server for development

scripts/            # Build and deployment scripts
docs/               # Documentation
```

### Key Architectural Patterns

**State Management**: Riverpod providers throughout. Provider hierarchy:
- Backend provider (FfiBackend for local Rust, NetworkBackend for remote, DisconnectedBackend for offline)
- Database provider (Drift SQLite instance, schema version 5)
- Equipment/Imaging/Sequence/Settings providers (23+ provider files)
- Session management with checkpoint recovery

**FFI Boundary**: Dart ↔ Rust via flutter_rust_bridge 2.11.1. Bindings auto-generated from `native/nightshade_native/bridge/src/lib.rs`.

**Database**: Drift ORM with SQLite. Tables:
- equipment_profiles, targets, imaging_sessions, captured_images, image_metadata
- sequences, sequence_nodes, sequence_checkpoints
- app_settings, weather_settings

**Sequencer**: Rust behavior tree with three node types:
- Instruction nodes (hardware actions: expose, slew, autofocus, filter change, etc.)
- Trigger nodes (parallel watchdogs: HFR monitor, guiding monitor, time triggers)
- Logic nodes (flow control: loop, parallel, conditional, recovery)

**Services** (23 service classes):
- DeviceService, ImagingService, SessionService, ProfileService
- PlateSolveService, CenteringService, FocusModelService
- WeatherRadarService, WeatherAlertService, CloudMotionAnalyzer
- SchedulerService, MosaicService, FlatWizardService
- BackupService, AutoSaveService, LoggingService, ErrorService

### Where to Make Changes

| Change Type | Location |
|-------------|----------|
| UI/Widgets (shared) | `packages/nightshade_app/` |
| Desktop-only UI | `apps/desktop/lib/` |
| Mobile-only UI | `apps/mobile/lib/` |
| Design system | `packages/nightshade_ui/` |
| Business logic | `packages/nightshade_core/lib/src/providers/` or `services/` |
| Models | `packages/nightshade_core/lib/src/models/` |
| Database | `packages/nightshade_core/lib/src/database/` |
| Planetarium/sky rendering | `packages/nightshade_planetarium/` |
| OTA updates | `packages/nightshade_updater/` |
| Remote control (WebRTC) | `packages/nightshade_webrtc/` |
| Plugin system | `packages/nightshade_plugins/` |
| Windows ASCOM | `native/nightshade_native/ascom/src/` |
| Linux/macOS INDI | `native/nightshade_native/indi/src/` |
| Cross-platform Alpaca | `native/nightshade_native/alpaca/src/` |
| Automation/Sequencing | `native/nightshade_native/sequencer/src/` |
| Image processing | `native/nightshade_native/imaging/src/` |
| Vendor SDKs | `native/nightshade_native/native/src/vendor/` |

## Tech Stack

**Dart/Flutter**:
- Flutter 3.24+
- Riverpod 2.5.1 (state management)
- go_router 14.0 (navigation)
- Drift 2.15 (SQLite ORM)
- freezed 2.4 (immutable models)
- flutter_rust_bridge 2.11.1 (FFI)

**Rust** (Edition 2021):
- tokio 1.35 (async runtime)
- serde 1.0 (serialization)
- flutter_rust_bridge 2.11.1 (FFI)
- windows 0.52 (Windows COM for ASCOM)
- quick-xml 0.31 (INDI XML parsing)
- reqwest 0.11 (HTTP for Alpaca)
- image 0.24 (image processing)

**Supported Vendor SDKs** (native crate):
- Camera: ZWO ASI, QHY, PlayerOne, SVBony, Atik, FLI, Moravian, Touptek
- Mount: SkyWatcher, iOptron, LX200 (serial)

## Troubleshooting

### FFI Code Generation (Windows)

If `flutter_rust_bridge_codegen generate` fails with `stdbool.h not found`:

```powershell
# Set CPATH before running codegen (adjust versions to match your installation)
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared"
flutter_rust_bridge_codegen generate
```

### FFI Code Generation (Linux)

If `flutter_rust_bridge_codegen generate` fails with missing headers:

```bash
# Set CPATH before running codegen (adjust to match your installation)
export CPATH="/usr/lib/clang/21/include"
flutter_rust_bridge_codegen generate
```

### DLL Hash Mismatches

If you get hash mismatch errors at runtime, Dart bindings and compiled Rust are out of sync. Always use `melos run dev` instead of `flutter run` directly after Rust changes.

### Clean Regeneration

When FRB issues persist:
```bash
flutter clean
rm -rf packages/nightshade_bridge/lib/src/*.dart
rm -rf packages/nightshade_bridge/lib/src/api/
cd native/nightshade_native
flutter_rust_bridge_codegen generate
```

See `docs/FRB_TROUBLESHOOTING.md` for detailed solutions.

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yml`) runs on push/PR to main:

| Job | Description |
|-----|-------------|
| Analyze | `melos run analyze` (Dart static analysis) |
| Dart Tests | `melos run test` (Flutter unit/widget tests) |
| Rust Tests | `cargo test --all-features` + `cargo clippy` |
| Format Check | Dart + Rust formatting validation |
| Build Test | Matrix build on Ubuntu, Windows, macOS |
| Code Coverage | LCOV report uploaded to Codecov |

## Notes

- LibRaw uses pre-compiled DLLs (avoid C++ toolchain complexity)
- Desktop entry point: `apps/desktop/lib/main.dart`
- Mobile entry point: `apps/mobile/lib/main.dart`
- Headless mode entry: `apps/desktop/lib/main_headless.dart`
- Profile/settings stored in platform-specific app data directory
- Version managed in `version.yaml` (single source of truth)
- Always run `melos run generate` after modifying models or FFI interfaces
- Validate Rust compiles before FRB codegen: `cargo check --package nightshade_bridge`
