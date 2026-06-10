#!/bin/sh
# Nightshade Pi appliance — one-shot first-boot setup.
#
# Runs once (stamp file guarded, plus ConditionPathExists in the unit).
# Its only real job is to make sure xvfb-run exists: the systemd unit wraps
# the Flutter daemon in xvfb-run (the GTK embedder needs a display even in
# headless app mode), and build_pi_image.sh can only bake xvfb into the
# image when the build host has qemu-user-static binfmt set up.
#
# It deliberately does NOT create the nightshade user or directories —
# systemd-sysusers (/etc/sysusers.d/nightshade.conf) and the unit's
# StateDirectory= handle those declaratively.
set -eu

STAMP=/var/lib/nightshade-firstboot.done

if [ -f "$STAMP" ]; then
  exit 0
fi

if command -v xvfb-run >/dev/null 2>&1; then
  echo "nightshade-firstboot: xvfb already present (baked into image)."
else
  echo "nightshade-firstboot: installing xvfb (needs network)..."
  # Wait briefly for apt to be able to resolve/download — first boot races
  # the Wi-Fi provisioning service. The unit also orders itself after
  # network-online.target, so this loop is a belt-and-braces retry.
  tries=0
  until apt-get update -qq && \
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq xvfb xauth; do
    tries=$((tries + 1))
    if [ "$tries" -ge 10 ]; then
      echo "nightshade-firstboot: FAILED to install xvfb after $tries tries." >&2
      echo "nightshade-headless will crash-loop until 'apt install xvfb' is" >&2
      echo "run manually. NOT writing the stamp so this retries next boot." >&2
      exit 1
    fi
    echo "nightshade-firstboot: apt failed (no network yet?), retry $tries/10 in 30s"
    sleep 30
  done
fi

touch "$STAMP"
echo "nightshade-firstboot: done."
