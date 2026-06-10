#!/usr/bin/env bash
# Build a flashable Raspberry Pi OS Lite (arm64) image with the Nightshade
# headless appliance pre-installed.
#
# Approach: loopback-mount surgery on an official base image (no pi-gen
# checkout, no chroot required for the core path). We:
#   1. copy + decompress the base image, grow the rootfs partition,
#   2. drop the (pre-built, arm64) release bundle into /opt/nightshade,
#   3. install the hardened systemd unit from ../systemd/, an env file with
#      a freshly generated auth token, sysusers/tmpfiles fragments that
#      create the `nightshade` user on first boot,
#   4. install the first-boot setup service (installs xvfb if missing) and
#      the Wi-Fi hotspot fallback provisioning service (provisioning/),
#   5. enable everything via wants-symlinks (no systemctl needed offline).
#
# Usage (run as root — loop mounts):
#   sudo ./build_pi_image.sh \
#     --base-image  ~/Downloads/2025-05-13-raspios-bookworm-arm64-lite.img.xz \
#     --bundle-tarball /path/to/nightshade-linux-arm64-<ver>.tar.gz \
#     --out         ./nightshade-pi-arm64.img \
#     [--hostname nightshade] [--grow-mb 2048] \
#     [--user pi --password 'raspberry'] [--enable-ssh] \
#     [--wifi-country US] [--allow-arch-mismatch]
#
# Required tools (Arch/CachyOS):  pacman -S --needed util-linux parted \
#     e2fsprogs dosfstools xz coreutils binutils rsync
#   (util-linux: losetup/sfdisk; binutils: readelf for the arch check.)
# Optional, for baking xvfb into the image instead of first-boot install:
#     pacman -S qemu-user-static qemu-user-static-binfmt
#
# ── The arm64 bundle: an honest note ────────────────────────────────────────
# scripts/docker_build_linux.sh produces an x86_64 bundle. There is NO
# verified arm64 cross-build path in this repo yet. To get the arm64 tarball
# this script needs, either:
#   a) run scripts/docker_build_linux.sh on an arm64 host (a Pi 4/5 with
#      8 GB + swap, or an arm64 CI runner / cloud VM):
#        docker run --rm -v "$PWD":/host:ro -v "$PWD/dist-linux":/out \
#          ghcr.io/cirruslabs/flutter:stable bash /host/scripts/docker_build_linux.sh
#      (the script is arch-agnostic; the bundle lands under
#       build/linux/arm64/release/bundle on arm64 hosts — the script's
#       hardcoded x64 path/tarball name will need the obvious arm64 fixup),
#   or
#   b) run the same container under emulation on this x86_64 box
#      (qemu-user-static + binfmt, `docker run --platform linux/arm64 ...`).
#      Works but is several hours; the Rust + Flutter AOT steps are the
#      slow part.
# This script verifies the bundle's ELF architecture and refuses an x86_64
# bundle unless --allow-arch-mismatch is passed (useful only for dry-running
# the image plumbing itself).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_SRC_DIR="$SCRIPT_DIR/../systemd"

BASE_IMAGE=""
BUNDLE_TARBALL=""
OUT_IMAGE=""
NEW_HOSTNAME="nightshade"
GROW_MB=2048
PI_USER=""
PI_PASSWORD=""
ENABLE_SSH=0
WIFI_COUNTRY=""
ALLOW_ARCH_MISMATCH=0

usage() { sed -n '2,35p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base-image)      BASE_IMAGE="${2:?}"; shift 2 ;;
    --bundle-tarball)  BUNDLE_TARBALL="${2:?}"; shift 2 ;;
    --out)             OUT_IMAGE="${2:?}"; shift 2 ;;
    --hostname)        NEW_HOSTNAME="${2:?}"; shift 2 ;;
    --grow-mb)         GROW_MB="${2:?}"; shift 2 ;;
    --user)            PI_USER="${2:?}"; shift 2 ;;
    --password)        PI_PASSWORD="${2:?}"; shift 2 ;;
    --enable-ssh)      ENABLE_SSH=1; shift ;;
    --wifi-country)    WIFI_COUNTRY="${2:?}"; shift 2 ;;
    --allow-arch-mismatch) ALLOW_ARCH_MISMATCH=1; shift ;;
    -h|--help)         usage 0 ;;
    *) echo "Unknown argument: $1" >&2; usage 1 ;;
  esac
done

[ -n "$BASE_IMAGE" ] && [ -n "$BUNDLE_TARBALL" ] && [ -n "$OUT_IMAGE" ] \
  || { echo "ERROR: --base-image, --bundle-tarball and --out are required." >&2; usage 1; }
[ -f "$BASE_IMAGE" ]     || { echo "ERROR: base image not found: $BASE_IMAGE" >&2; exit 1; }
[ -f "$BUNDLE_TARBALL" ] || { echo "ERROR: bundle tarball not found: $BUNDLE_TARBALL" >&2; exit 1; }
[ "$(id -u)" -eq 0 ]     || { echo "ERROR: must run as root (loop mounts)." >&2; exit 1; }

for tool in losetup sfdisk e2fsck resize2fs truncate readelf rsync tar; do
  command -v "$tool" >/dev/null 2>&1 \
    || { echo "ERROR: missing tool '$tool' (see header for pacman packages)" >&2; exit 1; }
done

# ── 0. Verify the bundle architecture BEFORE touching the image ─────────────
WORK="$(mktemp -d /tmp/nightshade-pi.XXXXXX)"
LOOPDEV=""
ROOT_MNT=""
cleanup() {
  set +e
  if [ -n "$ROOT_MNT" ]; then
    umount -R "$ROOT_MNT" 2>/dev/null
  fi
  [ -n "$LOOPDEV" ] && losetup -d "$LOOPDEV" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "== [0/7] bundle architecture check =="
mkdir -p "$WORK/bundle"
tar -xzf "$BUNDLE_TARBALL" -C "$WORK/bundle"
BUNDLE_EXE="$WORK/bundle/nightshade_desktop"
[ -f "$BUNDLE_EXE" ] || { echo "ERROR: nightshade_desktop missing from tarball" >&2; exit 1; }
ELF_MACHINE="$(readelf -h "$BUNDLE_EXE" | awk -F: '/Machine/ {gsub(/^[ \t]+/, "", $2); print $2}')"
echo "Bundle ELF machine: $ELF_MACHINE"
if ! printf '%s' "$ELF_MACHINE" | grep -qi 'aarch64'; then
  if [ "$ALLOW_ARCH_MISMATCH" -eq 1 ]; then
    echo "WARNING: bundle is NOT aarch64 ($ELF_MACHINE) — continuing because"
    echo "         --allow-arch-mismatch was passed. The image WILL NOT run"
    echo "         Nightshade on a Pi. Plumbing dry-run only."
  else
    echo "ERROR: bundle is '$ELF_MACHINE', not aarch64. A Raspberry Pi image" >&2
    echo "needs an arm64 build — see the header of this script for the two" >&2
    echo "honest ways to produce one. (--allow-arch-mismatch to override.)" >&2
    exit 1
  fi
fi

# ── 1. Copy + decompress base image ──────────────────────────────────────────
echo "== [1/7] base image -> $OUT_IMAGE =="
case "$BASE_IMAGE" in
  *.xz) command -v xz >/dev/null || { echo "ERROR: xz needed for .xz base" >&2; exit 1; }
        xz -dkc "$BASE_IMAGE" > "$OUT_IMAGE" ;;
  *.img) cp --reflink=auto "$BASE_IMAGE" "$OUT_IMAGE" ;;
  *) echo "ERROR: base image must be .img or .img.xz" >&2; exit 1 ;;
esac

# ── 2. Grow the image + rootfs partition ─────────────────────────────────────
# RPi OS images ship a rootfs with almost no free space; the bundle + xvfb
# need room. (RPi OS still auto-expands to fill the SD card on first boot.)
echo "== [2/7] grow rootfs by ${GROW_MB} MiB =="
truncate -s +"${GROW_MB}M" "$OUT_IMAGE"
# Partition 2 is the rootfs on RPi OS images; grow it to fill the file.
echo ', +' | sfdisk -N 2 --no-reread "$OUT_IMAGE" >/dev/null

LOOPDEV="$(losetup --find --show --partscan "$OUT_IMAGE")"
echo "Loop device: $LOOPDEV"
BOOT_PART="${LOOPDEV}p1"
ROOT_PART="${LOOPDEV}p2"
[ -b "$ROOT_PART" ] || { echo "ERROR: $ROOT_PART did not appear (partscan failed)" >&2; exit 1; }
e2fsck -pf "$ROOT_PART" >/dev/null || true
resize2fs "$ROOT_PART"

# ── 3. Mount ─────────────────────────────────────────────────────────────────
echo "== [3/7] mount =="
ROOT_MNT="$WORK/root"
mkdir -p "$ROOT_MNT"
mount "$ROOT_PART" "$ROOT_MNT"
# Bookworm mounts the firmware partition at /boot/firmware.
BOOT_MNT="$ROOT_MNT/boot/firmware"
[ -d "$BOOT_MNT" ] || BOOT_MNT="$ROOT_MNT/boot"
mount "$BOOT_PART" "$BOOT_MNT"

# ── 4. Install the application + unit + config ──────────────────────────────
echo "== [4/7] install Nightshade =="
install -d -m 0755 "$ROOT_MNT/opt/nightshade/bundle" "$ROOT_MNT/etc/nightshade"
rsync -a "$WORK/bundle/" "$ROOT_MNT/opt/nightshade/bundle/"
chown -R 0:0 "$ROOT_MNT/opt/nightshade"

# systemd unit (shared with the bare-metal install) + a Pi drop-in that
# orders it after the first-boot setup (which installs xvfb on first boot
# when it was not baked in below).
install -m 0644 "$SYSTEMD_SRC_DIR/nightshade-headless.service" \
  "$ROOT_MNT/etc/systemd/system/nightshade-headless.service"
install -d "$ROOT_MNT/etc/systemd/system/nightshade-headless.service.d"
cat > "$ROOT_MNT/etc/systemd/system/nightshade-headless.service.d/pi.conf" <<'EOF'
# Pi appliance ordering: first boot must finish (xvfb install, user
# creation via sysusers) before the daemon starts.
[Unit]
Wants=nightshade-firstboot.service
After=nightshade-firstboot.service
EOF

# Env file with a freshly generated auth token (mode fixed up at first boot
# by tmpfiles below, since the nightshade gid does not exist yet).
TOKEN="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
sed "s/^NIGHTSHADE_AUTH_TOKEN=.*/NIGHTSHADE_AUTH_TOKEN=$TOKEN/" \
  "$SYSTEMD_SRC_DIR/headless.env.example" > "$ROOT_MNT/etc/nightshade/headless.env"
chmod 0600 "$ROOT_MNT/etc/nightshade/headless.env"
echo "Generated auth token (also in /etc/nightshade/headless.env on the image):"
echo "  $TOKEN"

# Create the service user at first boot, host-side-uid-free: sysusers makes
# the user, tmpfiles fixes ownership/modes that need the new uid/gid. The
# unit's StateDirectory=nightshade handles /var/lib/nightshade itself.
cat > "$ROOT_MNT/etc/sysusers.d/nightshade.conf" <<'EOF'
u nightshade - "Nightshade appliance" /var/lib/nightshade
m nightshade dialout
m nightshade video
m nightshade plugdev
EOF
cat > "$ROOT_MNT/etc/tmpfiles.d/nightshade.conf" <<'EOF'
z /etc/nightshade/headless.env 0640 root nightshade -
EOF

# ── 5. First-boot setup + Wi-Fi provisioning ─────────────────────────────────
echo "== [5/7] first-boot + provisioning services =="
install -d -m 0755 "$ROOT_MNT/usr/local/lib/nightshade"
install -m 0755 "$SCRIPT_DIR/firstboot/nightshade-firstboot.sh" \
  "$ROOT_MNT/usr/local/lib/nightshade/nightshade-firstboot.sh"
install -m 0644 "$SCRIPT_DIR/firstboot/nightshade-firstboot.service" \
  "$ROOT_MNT/etc/systemd/system/nightshade-firstboot.service"
install -m 0755 "$SCRIPT_DIR/provisioning/nightshade-netprovision.sh" \
  "$ROOT_MNT/usr/local/lib/nightshade/nightshade-netprovision.sh"
install -m 0755 "$SCRIPT_DIR/provisioning/provision_portal.py" \
  "$ROOT_MNT/usr/local/lib/nightshade/provision_portal.py"
install -m 0644 "$SCRIPT_DIR/provisioning/nightshade-netprovision.service" \
  "$ROOT_MNT/etc/systemd/system/nightshade-netprovision.service"
# Poor-man's captive portal: while the NM hotspot is up, its shared-mode
# dnsmasq resolves EVERY name to the portal address so phones pop the
# "sign in to network" sheet. Harmless when no hotspot is active.
install -d "$ROOT_MNT/etc/NetworkManager/dnsmasq-shared.d"
cat > "$ROOT_MNT/etc/NetworkManager/dnsmasq-shared.d/nightshade-captive.conf" <<'EOF'
address=/#/10.42.0.1
EOF

# Enable units offline (equivalent of `systemctl enable`).
WANTS="$ROOT_MNT/etc/systemd/system/multi-user.target.wants"
install -d "$WANTS"
ln -sf /etc/systemd/system/nightshade-headless.service "$WANTS/"
ln -sf /etc/systemd/system/nightshade-firstboot.service "$WANTS/"
ln -sf /etc/systemd/system/nightshade-netprovision.service "$WANTS/"

# Optional: bake xvfb into the image now via qemu-user-static chroot, so
# first boot does not need to apt-get it. Best-effort — skipped (with a
# clear message) when binfmt/qemu is not set up on this build host.
if chroot "$ROOT_MNT" /usr/bin/true 2>/dev/null; then
  echo "qemu binfmt works — installing xvfb into the image now"
  mount -t proc proc "$ROOT_MNT/proc"
  mount -t sysfs sys "$ROOT_MNT/sys"
  mount --bind /dev "$ROOT_MNT/dev"
  if chroot "$ROOT_MNT" sh -c \
      'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb xauth'; then
    echo "xvfb baked in — first boot will skip the package install."
  else
    echo "WARNING: chroot apt install failed (no network?); first boot will install xvfb instead."
  fi
  umount "$ROOT_MNT/proc" "$ROOT_MNT/sys" "$ROOT_MNT/dev"
else
  echo "NOTE: arm64 chroot not runnable on this host (install qemu-user-static"
  echo "      + qemu-user-static-binfmt to bake xvfb in). The first-boot service"
  echo "      will apt-get install xvfb once the Pi is online."
fi

# ── 6. Hostname / ssh / first-user (RPi OS specifics) ───────────────────────
echo "== [6/7] host identity =="
echo "$NEW_HOSTNAME" > "$ROOT_MNT/etc/hostname"
sed -i "s/\braspberrypi\b/$NEW_HOSTNAME/g" "$ROOT_MNT/etc/hosts" || true
if [ "$ENABLE_SSH" -eq 1 ]; then
  touch "$BOOT_MNT/ssh"
  echo "SSH enabled."
fi
# Since Bullseye, RPi OS has no default user; headless first boot needs
# userconf.txt or the boot stalls at the rename-user wizard.
if [ -n "$PI_USER" ]; then
  [ -n "$PI_PASSWORD" ] || { echo "ERROR: --user needs --password" >&2; exit 1; }
  command -v openssl >/dev/null || { echo "ERROR: openssl needed for --password" >&2; exit 1; }
  printf '%s:%s\n' "$PI_USER" "$(openssl passwd -6 "$PI_PASSWORD")" \
    > "$BOOT_MNT/userconf.txt"
  echo "Wrote userconf.txt for user '$PI_USER'."
else
  echo "NOTE: no --user given. Pure-appliance images boot fine without one"
  echo "      (the wizard only blocks console login, not system services),"
  echo "      but you will have no SSH/console account for debugging."
fi
if [ -n "$WIFI_COUNTRY" ]; then
  # Regulatory domain — required before the Pi will transmit as an AP.
  sed -i "/^REGDOMAIN=/d" "$ROOT_MNT/etc/default/crda" 2>/dev/null || true
  echo "country=$WIFI_COUNTRY" > "$ROOT_MNT/etc/nightshade/wifi-country"
  if ! grep -q 'cfg80211.ieee80211_regdom' "$BOOT_MNT/cmdline.txt"; then
    sed -i "1s/\$/ cfg80211.ieee80211_regdom=$WIFI_COUNTRY/" "$BOOT_MNT/cmdline.txt"
  fi
  echo "Wi-Fi regulatory domain set to $WIFI_COUNTRY."
else
  echo "WARNING: no --wifi-country. The fallback hotspot may refuse to start"
  echo "         on some kernels until a regulatory domain is set."
fi

# ── 7. Unmount + done ────────────────────────────────────────────────────────
echo "== [7/7] finalize =="
sync
umount "$BOOT_MNT"
umount "$ROOT_MNT"
ROOT_MNT=""
losetup -d "$LOOPDEV"
LOOPDEV=""

echo
echo "DONE -> $OUT_IMAGE"
echo "Flash:   sudo dd if=$OUT_IMAGE of=/dev/sdX bs=4M conv=fsync status=progress"
echo "         (or use rpi-imager / balenaEtcher)"
echo "First boot: if no known Wi-Fi joins within 90 s, look for the"
echo "'Nightshade-XXXX' hotspot (password: nightshade) and browse to"
echo "http://10.42.0.1 to enter your home Wi-Fi credentials."
