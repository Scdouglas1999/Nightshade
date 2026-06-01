#!/usr/bin/env bash
# Linux release build for Nightshade, run inside the cirruslabs/flutter image.
# Builds a clean source snapshot of the committed HEAD (mounted read-only at
# /host) so the host's Windows .dart_tool/build dirs are never touched, then
# emits a packaged bundle tarball to /out.
set -euo pipefail

echo "== [1/7] apt deps =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev libsecret-1-dev libjsoncpp-dev \
  curl git tar ca-certificates

echo "== [2/7] rust toolchain =="
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
# shellcheck disable=SC1091
. "$HOME/.cargo/env"
rustc --version

echo "== [3/7] clean source snapshot from committed HEAD =="
git config --global --add safe.directory /host
rm -rf /work && mkdir -p /work
git -C /host archive HEAD | tar -x -C /work
cd /work

echo "== [4/7] flutter linux desktop =="
flutter config --enable-linux-desktop >/dev/null
flutter --version

echo "== [5/7] melos bootstrap =="
dart pub global activate melos
export PATH="$PATH:$HOME/.pub-cache/bin"
dart run melos bootstrap

echo "== [6/7] rust bridge (release) =="
cargo build --release --manifest-path native/nightshade_native/bridge/Cargo.toml

echo "== [7/7] flutter build linux (release) =="
cd apps/desktop
flutter build linux --release

BUNDLE=build/linux/x64/release/bundle
echo "== bundle contents =="
ls -lah "$BUNDLE"
# Ensure the Rust shared library is present in the bundle's lib/ (mirror the
# Windows packaging step, which copies the bridge DLL next to the exe).
SO=$(find /work/native/nightshade_native/target/release -maxdepth 1 -name 'libnightshade_bridge.so' -o -name 'nightshade_bridge.so' 2>/dev/null | head -1 || true)
if [ -n "${SO:-}" ] && [ ! -f "$BUNDLE/lib/$(basename "$SO")" ]; then
  echo "Copying $(basename "$SO") into bundle/lib/"
  mkdir -p "$BUNDLE/lib"
  cp "$SO" "$BUNDLE/lib/"
fi

mkdir -p /out
cd "$BUNDLE"
tar -czf /out/nightshade-linux-x64-3.0.0.tar.gz .
echo "DONE -> /out/nightshade-linux-x64-3.0.0.tar.gz"
ls -lah /out/
