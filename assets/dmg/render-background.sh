#!/bin/zsh
# Renders background.html into background.tiff (1x + 2x in one file, so Retina Finder windows stay sharp).
# Needs Google Chrome; run after editing background.html and commit the TIFF (release.sh only reads it).
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
for SCALE in 1 2; do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=660,420 \
    --force-device-scale-factor=$SCALE --virtual-time-budget=1500 \
    --screenshot="$WORK/bg-$SCALE.png" "file://$PWD/background.html" >/dev/null 2>&1
done
tiffutil -cathidpicheck "$WORK/bg-1.png" "$WORK/bg-2.png" -out background.tiff >/dev/null
echo "✓ background.tiff"
