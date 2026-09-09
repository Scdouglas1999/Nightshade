#!/usr/bin/env bash
# Render every mockup to PNG with headless Chromium.
#   docs/design/overhaul/mockups/render.sh            # all pages, all themes
#   docs/design/overhaul/mockups/render.sh tonight    # one page
# Output: mockups/png/<page>[-<theme>].png at the app's default window size (1600x900),
# narrow.html at 700x900. These PNGs are the visual acceptance reference for 07-implementation-waves.md.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="${CHROME:-$(command -v chromium || command -v chromium-browser || command -v google-chrome)}"
mkdir -p png
python3 ../tools/check_tokens.py >/dev/null || { echo "token check failed; fix design-tokens.json first"; exit 1; }

render() {  # page theme width height
  local page="$1" theme="$2" w="$3" h="$4"
  local out="png/${page}${theme:+-$theme}.png"
  local url="file://$PWD/${page}.html${theme:+?theme=$theme}"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size="${w},${h}" --screenshot="$out" "$url" >/dev/null 2>&1
  echo "wrote $out"
}

pages=("$@")
if [ ${#pages[@]} -eq 0 ]; then
  pages=(tonight tonight-empty imaging sequencer equipment plan settings components)
fi
for p in "${pages[@]}"; do
  case "$p" in
    narrow) render narrow "" 700 900; render narrow redNight 700 900 ;;
    components) render components "" 1600 1900; render components light 1600 1900 ;;
    tonight|settings) render "$p" "" 1600 900; render "$p" light 1600 900; render "$p" redNight 1600 900 ;;
    imaging|sequencer|equipment) render "$p" "" 1600 900; render "$p" light 1600 900 ;;
    *) render "$p" "" 1600 900 ;;
  esac
done
[ ${#@} -eq 0 ] && { render narrow "" 700 900; render narrow redNight 700 900; }
true
