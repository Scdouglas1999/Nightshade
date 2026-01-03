# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Nightshade 2.0 is a cross-platform astrophotography suite built with Flutter (Dart) and Rust. It provides imaging sequencing, device control, and sky visualization for Windows, macOS, Linux desktops, and iOS/Android mobile platforms.

## Build Commands

The project uses **Melos** for monorepo management. All commands run from the repository root:

```bash
# Bootstrap workspace (install dependencies, generate code)
melos bootstrap

# Code quality
melos run analyze    # Run dart analyze
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

### Platform-Specific Build Scripts

- `scripts/dev.ps1` - Windows development build (FRB + Rust + copy DLLs + run)
- `scripts/build_native.ps1` - Windows Rust build only
- `scripts/build_native.sh` - Linux/macOS Rust build (auto-detects architecture)
- `scripts/copy_libraw.ps1` - Copy LibRaw DLL dependencies

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
├── desktop/         # Flutter Windows/macOS/Linux app
└── mobile/          # Flutter iOS/Android companion app

packages/
├── nightshade_app/       # Shared UI shell
├── nightshade_core/      # Business logic, database, providers, services
├── nightshade_bridge/    # Dart FFI bindings to Rust (flutter_rust_bridge)
├── nightshade_ui/        # Design system & shared widgets
├── nightshade_planetarium/  # GPU-rendered sky visualization
├── nightshade_plugins/   # Plugin host & API
└── nightshade_webrtc/    # P2P remote control

native/nightshade_native/
├── bridge/       # FFI entry point (cdylib)
├── sequencer/    # Behavior tree automation engine
├── ascom/        # Windows COM ASCOM drivers
├── indi/         # Linux/macOS INDI protocol
├── alpaca/       # ASCOM Alpaca HTTP protocol
├── imaging/      # Image processing (LibRaw FFI, FITS)
└── native/       # Vendor SDK FFI bindings
```

### Key Architectural Patterns

**State Management**: Riverpod providers throughout. Provider hierarchy:
- Backend provider (FfiBackend for local Rust, NetworkBackend for remote, DisconnectedBackend for offline)
- Database provider (Drift SQLite instance)
- Equipment/Imaging/Sequence/Settings providers

**FFI Boundary**: Dart ↔ Rust via flutter_rust_bridge 2.0. Bindings auto-generated from `native/nightshade_native/bridge/src/lib.rs`.

**Database**: Drift ORM with tables for equipment_profiles, targets, sessions, images, sequences, settings.

**Sequencer**: Rust behavior tree with three node types:
- Instruction nodes (hardware actions)
- Trigger nodes (parallel watchdogs)
- Logic nodes (flow control)

### Where to Make Changes

| Change Type | Location |
|-------------|----------|
| UI/Widgets (shared) | `packages/nightshade_app/` |
| Desktop-only UI | `apps/desktop/lib/` |
| Design system | `packages/nightshade_ui/` |
| Business logic | `packages/nightshade_core/lib/src/providers/` or `services/` |
| Models | `packages/nightshade_core/lib/src/models/` |
| Database | `packages/nightshade_core/lib/src/database/` |
| Windows ASCOM | `native/nightshade_native/ascom/src/` |
| Linux INDI | `native/nightshade_native/indi/src/` |
| Cross-platform Alpaca | `native/nightshade_native/alpaca/src/` |
| Automation/Sequencing | `native/nightshade_native/sequencer/src/` |
| Image processing | `native/nightshade_native/imaging/src/` |

## Tech Stack

**Dart/Flutter**: Flutter 3.0+, Riverpod 2.5, go_router 14, Drift 2.15, freezed 2.4, flutter_rust_bridge 2.0

**Rust**: Edition 2021, tokio 1.35, serde, flutter_rust_bridge 2.11, windows crate (ASCOM), quick-xml (INDI), reqwest (Alpaca)

## Troubleshooting

### FFI Code Generation (Windows)

If `flutter_rust_bridge_codegen generate` fails with `stdbool.h not found`:

```powershell
# Set CPATH before running codegen (adjust versions to match your installation)
$env:CPATH = "C:\Program Files\LLVM\lib\clang\21\include;C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.43.34808\include;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.22621.0\shared"
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

## Notes

- LibRaw uses pre-compiled DLLs (avoid C++ toolchain complexity)
- Desktop entry point: `apps/desktop/lib/main.dart`
- Headless mode entry: `apps/desktop/lib/main_headless.dart`
- Profile/settings stored in `%APPDATA%/Nightshade/profiles/`
- Always run `melos run generate` after modifying models or FFI interfaces
- Validate Rust compiles before FRB codegen: `cargo check --package nightshade_bridge`
