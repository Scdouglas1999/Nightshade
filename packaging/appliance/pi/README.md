# Nightshade Raspberry Pi appliance image

Builds a flashable Raspberry Pi OS Lite (arm64) image with the Nightshade
headless server pre-installed: boot the Pi at the telescope, pair from the
mobile app, image all night. No keyboard, monitor, or SSH session required.

## What ends up on the image

| Piece | Path on the Pi | Source |
|---|---|---|
| App bundle (arm64) | `/opt/nightshade/bundle/` | your release tarball |
| Hardened systemd unit | `/etc/systemd/system/nightshade-headless.service` | `../systemd/nightshade-headless.service` (shared with bare-metal installs) |
| Config + generated auth token | `/etc/nightshade/headless.env` | `../systemd/headless.env.example` |
| Service user (created at first boot) | `sysusers.d/nightshade.conf` | declarative — no chroot `useradd` needed |
| First-boot setup (installs xvfb if not baked in) | `nightshade-firstboot.{sh,service}` | `firstboot/` |
| Wi-Fi hotspot fallback provisioning | `nightshade-netprovision.{sh,service}`, `provision_portal.py` | `provisioning/` |
| Captive-DNS for the hotspot | `/etc/NetworkManager/dnsmasq-shared.d/nightshade-captive.conf` | written by the build script |

## Prerequisites on the build box (Arch / CachyOS)

```sh
sudo pacman -S --needed util-linux parted e2fsprogs dosfstools xz coreutils binutils rsync openssl
# Optional — lets the build bake xvfb into the image via an arm64 chroot,
# so first boot needs no internet:
sudo pacman -S --needed qemu-user-static qemu-user-static-binfmt
```

Plus:

1. **Base image** — Raspberry Pi OS **Lite, 64-bit (Bookworm)** from
   <https://www.raspberrypi.com/software/operating-systems/>. Bookworm is
   required: the provisioning flow drives **NetworkManager**, which is the
   default network stack from Bookworm on.
2. **An arm64 release bundle tarball** — see the next section. This is the
   one input we cannot fully produce on this x86_64 box (honestly).

## Getting the arm64 bundle (the honest part)

`scripts/docker_build_linux.sh` is the canonical Linux release pipeline
(rust `cargo build --release` → `melos bootstrap` → `flutter build linux
--release` → smoke test under xvfb → tarball). It is architecture-agnostic
but has only been exercised for x86_64, and Flutter does not cross-compile
Linux desktop targets. Two real options:

* **On an arm64 host** (Pi 4/5 with 8 GB and swap, or any arm64 VM/CI
  runner) run the standard flow:

  ```sh
  docker run --rm -v "$PWD":/host:ro -v "$PWD/dist-linux":/out \
    ghcr.io/cirruslabs/flutter:stable bash /host/scripts/docker_build_linux.sh
  ```

  On arm64 the Flutter bundle lands in `build/linux/arm64/release/bundle`;
  the script's hardcoded `x64` bundle path and `-x64-` tarball name need
  the obvious one-line fixups (kept out of the script here so the x64
  release path stays untouched while other work is in flight).

* **Emulated on this box**: install `qemu-user-static{,-binfmt}` and add
  `--platform linux/arm64` to the same `docker run`. This works but takes
  hours (AOT compile + Rust release build under qemu).

`build_pi_image.sh` **verifies the ELF architecture** of
`nightshade_desktop` in the tarball and refuses an x86_64 bundle unless you
pass `--allow-arch-mismatch` (only useful to dry-run the image plumbing).

## Building the image

```sh
sudo ./build_pi_image.sh \
  --base-image     ~/Downloads/2025-05-13-raspios-bookworm-arm64-lite.img.xz \
  --bundle-tarball ./nightshade-linux-arm64-4.0.0.tar.gz \
  --out            ./nightshade-pi-arm64.img \
  --hostname       nightshade \
  --wifi-country   US \
  --enable-ssh --user pi --password 'change-me'
```

Notes:

* Run as root (loopback mounts). The script grows the rootfs by
  `--grow-mb` (default 2048) to fit the bundle; RPi OS still auto-expands
  to fill the whole SD card on first boot.
* The generated **auth token is printed at the end of the build** and
  stored in `/etc/nightshade/headless.env` on the image. The mobile app's
  pairing flow doesn't need it (pairing codes print to the journal because
  `NIGHTSHADE_PAIRING_PRINT_CODES=true`), but API/cURL access does.
* `--wifi-country` is strongly recommended — without a regulatory domain
  some kernels refuse to start the fallback **hotspot**.
* `--user/--password` writes `userconf.txt`; without it the appliance
  still runs (services are unaffected by the first-run user wizard) but
  you have no SSH/console account for debugging.
* If qemu binfmt is available, xvfb is baked in during the build;
  otherwise the **first boot needs internet once** to
  `apt install xvfb` (the daemon is ordered after that step, so it simply
  starts a few minutes later on the very first boot).

Flash with `rpi-imager`, balenaEtcher, or:

```sh
sudo dd if=nightshade-pi-arm64.img of=/dev/sdX bs=4M conv=fsync status=progress
```

## First boot, from the user's couch

1. Power the Pi. If Ethernet is plugged in or a known Wi-Fi profile
   exists, it's online within a minute — skip to step 4.
2. No network after ~90 s → the Pi raises a WPA2 hotspot
   **`Nightshade-XXXX`** (password **`nightshade`**, XXXX = last 4 of the
   Wi-Fi MAC).
3. Join it with your phone. The captive sheet pops automatically (wildcard
   DNS → portal); if not, browse to **http://10.42.0.1**. Pick your home
   Wi-Fi, enter the password, submit. The hotspot drops, the Pi joins your
   network (on a wrong password the hotspot returns within a minute with
   an error banner — just retry).
4. Open the Nightshade mobile app: the server advertises
   `_nightshade._tcp` over mDNS and UDP beacons on 45679, so it appears in
   discovery. Pair; the pairing code prints to the Pi's journal
   (`journalctl -u nightshade-headless`) and on accessory-less setups the
   in-app pairing flow handles it.

## Day-2 operations

* Logs: `journalctl -fu nightshade-headless`
* Config: `/etc/nightshade/headless.env` (TLS, OTA server, scoped tokens,
  push config path — see comments in the file), then
  `systemctl restart nightshade-headless`.
* Updates: set `NIGHTSHADE_UPDATE_SERVER` (+ optional
  `NIGHTSHADE_UPDATE_CHANNEL`) in the env file to enable the OTA endpoints
  (`/api/system/update/*`) that the mobile app drives; or re-run the
  bare-metal `../systemd/install.sh --tarball <new>.tar.gz` over SSH.
* Re-provision Wi-Fi (moved house / new router): the fallback hotspot
  comes back automatically whenever no known network connects within 90 s
  of boot. To force it: `nmcli connection delete <old-ssid>` and reboot.

## Verification status (what was actually tested)

* `bash -n` on all shell scripts and `python3 -m py_compile` on the portal
  pass on this machine; `systemd-analyze verify` was run against the
  units where the local systemd allows it.
* The **full image build and on-Pi boot were not exercised here** — this
  workstation has no base image, no arm64 bundle, and image building
  requires root loop devices. The script is written to fail loudly at
  every step (arch check, missing tools, partition surgery), so a first
  real run will surface problems instead of producing a silently broken
  image. Treat the first build as a validation run.
