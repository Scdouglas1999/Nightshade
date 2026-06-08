#!/usr/bin/env bash
# Nightshade Development Build Script (Linux/macOS)
# ================================================
# Linux/macOS counterpart of scripts/dev.ps1. Keeps native + Flutter in sync:
#   1. (optional) Regenerates Flutter Rust Bridge bindings
#   2. Rebuilds the Rust native library (release)
#   3. Runs / builds the Flutter desktop app
#
# The Linux desktop CMake (apps/desktop/linux/CMakeLists.txt) automatically
# bundles native/nightshade_native/target/release/libnightshade_bridge.so into
# the app bundle, so no manual DLL/so copying is needed here (unlike dev.ps1).
# libraw is linked from the system package (libraw), so it does not need bundling.
#
# Usage:
#   ./scripts/dev.sh              # build native + run the app (debug)
#   ./scripts/dev.sh --release    # build native + run release
#   ./scripts/dev.sh --no-run     # build native + flutter build, don't run
#   ./scripts/dev.sh --skip-frb   # skip FRB regen (faster when only Dart/Rust impl changed)
#   ./scripts/dev.sh --clean      # flutter clean + cargo clean first

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$ROOT/native/nightshade_native"
DESKTOP_DIR="$ROOT/apps/desktop"

NO_RUN=0; SKIP_FRB=0; RELEASE=0; CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --no-run)   NO_RUN=1 ;;
    --skip-frb) SKIP_FRB=1 ;;
    --release)  RELEASE=1 ;;
    --clean)    CLEAN=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[36m==> %s\033[0m\n' "$1"; }
ok()   { printf '  \033[32m[OK]\033[0m %s\n' "$1"; }

if [[ $CLEAN -eq 1 ]]; then
  step "Cleaning build artifacts..."
  ( cd "$DESKTOP_DIR" && flutter clean >/dev/null 2>&1 || true ); ok "Flutter cleaned"
  ( cd "$NATIVE_DIR" && cargo clean >/dev/null 2>&1 || true );    ok "Cargo cleaned"
fi

if [[ $SKIP_FRB -eq 0 ]]; then
  step "Regenerating Flutter Rust Bridge bindings..."
  if command -v flutter_rust_bridge_codegen >/dev/null 2>&1; then
    ( cd "$NATIVE_DIR" && flutter_rust_bridge_codegen generate )
    ok "FRB bindings regenerated"
  else
    echo "  flutter_rust_bridge_codegen not found; install with:" >&2
    echo "    cargo install flutter_rust_bridge_codegen --version 2.11.1 --locked" >&2
    exit 1
  fi
fi

step "Building Rust native library (release)..."
( cd "$NATIVE_DIR" && cargo build --release --package nightshade_bridge )
ok "libnightshade_bridge.so built"

cd "$DESKTOP_DIR"
if [[ $NO_RUN -eq 1 ]]; then
  step "Building Flutter Linux bundle..."
  if [[ $RELEASE -eq 1 ]]; then flutter build linux --release; else flutter build linux --debug; fi
  ok "Build complete — bundle in build/linux/x64/$([[ $RELEASE -eq 1 ]] && echo release || echo debug)/bundle"
else
  step "Running Flutter app on Linux..."
  if [[ $RELEASE -eq 1 ]]; then flutter run -d linux --release; else flutter run -d linux; fi
fi
