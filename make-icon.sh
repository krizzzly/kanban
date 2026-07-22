#!/usr/bin/env bash
# Regenerates AppIcon.icns from the Hermes logo SVG. Renders the (non-square) vector at high
# resolution via Inkscape, fits it with padding onto a 1024² transparent square, then builds the
# macOS iconset. Requires: inkscape, imagemagick (magick), iconutil.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SVG="${1:-/Users/christianhiller/code/hermes/extension/icons/icon.svg}"
WORK="$(mktemp -d)/AppIcon"
trap 'rm -rf "$(dirname "$WORK")"' EXIT
mkdir -p "$WORK.iconset"

echo "==> rendering $SVG"
inkscape "$SVG" --export-type=png --export-filename="$WORK/src.png" -w 2048 >/dev/null 2>&1

# Fit within 924px and center on a 1024² transparent square (~5% padding).
magick "$WORK/src.png" -resize 924x924 -background none -gravity center -extent 1024x1024 "$WORK/icon-1024.png"

# name:size for each required iconset slot
for entry in \
  "icon_16x16:16" "icon_16x16@2x:32" "icon_32x32:32" "icon_32x32@2x:64" \
  "icon_128x128:128" "icon_128x128@2x:256" "icon_256x256:256" "icon_256x256@2x:512" \
  "icon_512x512:512" "icon_512x512@2x:1024"; do
  name="${entry%%:*}"; sz="${entry##*:}"
  magick "$WORK/icon-1024.png" -resize "${sz}x${sz}" "$WORK.iconset/${name}.png"
done

iconutil -c icns "$WORK.iconset" -o "$ROOT/AppIcon.icns"
echo "==> wrote $ROOT/AppIcon.icns"
