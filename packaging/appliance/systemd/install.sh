#!/usr/bin/env bash
# Install the Nightshade headless appliance on a systemd Linux host.
#
# Usage:
#   sudo ./install.sh --tarball /path/to/nightshade-linux-<arch>-<ver>.tar.gz
#   sudo ./install.sh --bundle-dir /path/to/build/linux/x64/release/bundle
#   sudo ./install.sh                # unit/user/dirs only, bundle already in place
#
# What it does:
#   1. Creates the dedicated `nightshade` system user (+ device-access groups).
#   2. Creates /opt/nightshade/bundle, /var/lib/nightshade, /etc/nightshade.
#   3. Unpacks the release tarball (from scripts/docker_build_linux.sh) into
#      /opt/nightshade/bundle.
#   4. Installs nightshade-headless.service and /etc/nightshade/headless.env
#      (generating a random auth token on first install).
#   5. Enables + starts the service.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_ROOT=/opt/nightshade
BUNDLE_DIR="$INSTALL_ROOT/bundle"
STATE_DIR=/var/lib/nightshade
CONF_DIR=/etc/nightshade
ENV_FILE="$CONF_DIR/headless.env"
UNIT_NAME=nightshade-headless.service
SERVICE_USER=nightshade

TARBALL=""
SRC_BUNDLE_DIR=""
NO_START=0

usage() { sed -n '2,12p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tarball)    TARBALL="${2:?--tarball needs a path}"; shift 2 ;;
    --bundle-dir) SRC_BUNDLE_DIR="${2:?--bundle-dir needs a path}"; shift 2 ;;
    --no-start)   NO_START=1; shift ;;
    -h|--help)    usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: must run as root (sudo $0 ...)" >&2
  exit 1
fi

if ! command -v systemctl >/dev/null 2>&1; then
  echo "ERROR: systemctl not found — this installer targets systemd hosts." >&2
  exit 1
fi

if ! command -v xvfb-run >/dev/null 2>&1; then
  echo "WARNING: xvfb-run not found. The unit wraps the daemon in xvfb-run" >&2
  echo "         (the Flutter GTK embedder needs a display even headless)." >&2
  echo "         Install it first: Debian/RPi OS: apt install xvfb" >&2
  echo "                           Arch:          pacman -S xorg-server-xvfb" >&2
fi

echo "== [1/5] service user =="
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$STATE_DIR" --create-home \
    --shell /usr/sbin/nologin "$SERVICE_USER"
  echo "Created system user '$SERVICE_USER'"
else
  echo "User '$SERVICE_USER' already exists"
fi
# Device-access groups for cameras / mounts / focusers. Not all distros have
# all three; add the ones that exist.
for grp in dialout video plugdev; do
  if getent group "$grp" >/dev/null 2>&1; then
    usermod -aG "$grp" "$SERVICE_USER"
  fi
done

echo "== [2/5] directories =="
mkdir -p "$BUNDLE_DIR" "$STATE_DIR" "$CONF_DIR"
chown "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR"
chmod 750 "$STATE_DIR"

echo "== [3/5] application bundle =="
if [ -n "$TARBALL" ]; then
  [ -f "$TARBALL" ] || { echo "ERROR: tarball not found: $TARBALL" >&2; exit 1; }
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR"
  tar -xzf "$TARBALL" -C "$BUNDLE_DIR"
elif [ -n "$SRC_BUNDLE_DIR" ]; then
  [ -d "$SRC_BUNDLE_DIR" ] || { echo "ERROR: bundle dir not found: $SRC_BUNDLE_DIR" >&2; exit 1; }
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR"
  cp -a "$SRC_BUNDLE_DIR/." "$BUNDLE_DIR/"
else
  echo "No --tarball/--bundle-dir given; assuming bundle already at $BUNDLE_DIR"
fi
if [ ! -x "$BUNDLE_DIR/nightshade_desktop" ]; then
  echo "ERROR: $BUNDLE_DIR/nightshade_desktop missing or not executable." >&2
  echo "Build it with scripts/docker_build_linux.sh and pass --tarball." >&2
  exit 1
fi
# Bundle is read-only at runtime; root-owned keeps the OTA updater honest
# (in-place OTA from the service is not possible with this layout — apply
# updates by re-running install.sh with a new tarball, or relax ownership).
chown -R root:root "$INSTALL_ROOT"

echo "== [4/5] config + unit =="
if [ ! -f "$ENV_FILE" ]; then
  install -m 0640 -o root -g "$SERVICE_USER" \
    "$SCRIPT_DIR/headless.env.example" "$ENV_FILE"
  # First install: replace the placeholder with a real random token so the
  # box is never accidentally exposed with a known credential.
  TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sed -i "s/^NIGHTSHADE_AUTH_TOKEN=.*/NIGHTSHADE_AUTH_TOKEN=$TOKEN/" "$ENV_FILE"
  echo "Wrote $ENV_FILE with a freshly generated auth token."
  echo "Read it with: sudo grep NIGHTSHADE_AUTH_TOKEN $ENV_FILE"
else
  echo "$ENV_FILE already exists — leaving it untouched."
fi
install -m 0644 "$SCRIPT_DIR/nightshade-headless.service" \
  "/etc/systemd/system/$UNIT_NAME"
systemctl daemon-reload

echo "== [5/5] enable + start =="
systemctl enable "$UNIT_NAME"
if [ "$NO_START" -eq 1 ]; then
  echo "Skipping start (--no-start). Start later with:"
  echo "  sudo systemctl start $UNIT_NAME"
else
  systemctl restart "$UNIT_NAME"
  sleep 2
  systemctl --no-pager --lines=10 status "$UNIT_NAME" || true
fi

echo
echo "Done. Useful commands:"
echo "  journalctl -fu $UNIT_NAME        # live logs (pairing codes print here)"
echo "  sudo systemctl restart $UNIT_NAME"
echo "  curl http://127.0.0.1:\${NIGHTSHADE_PORT:-8080}/api/status"
