#!/bin/bash
# Regenerate Fauxcus.icns and the menu bar template PNGs from the SVG sources
# in Resources/icon/. Run after editing those SVGs.
set -euo pipefail
cd "$(dirname "$0")/.."

INKSCAPE=/opt/homebrew/bin/inkscape
ICONSET=build/Fauxcus.iconset

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    "$INKSCAPE" -w "$size" -h "$size" Resources/icon/appicon.svg \
        -o "$ICONSET/icon_${size}x${size}.png" 2>/dev/null
    double=$((size * 2))
    "$INKSCAPE" -w "$double" -h "$double" Resources/icon/appicon.svg \
        -o "$ICONSET/icon_${size}x${size}@2x.png" 2>/dev/null
done
iconutil -c icns "$ICONSET" -o Resources/Fauxcus.icns

"$INKSCAPE" -w 18 -h 18 Resources/icon/menubar.svg -o Resources/MenuBarIcon.png 2>/dev/null
"$INKSCAPE" -w 36 -h 36 Resources/icon/menubar.svg -o "Resources/MenuBarIcon@2x.png" 2>/dev/null

"$INKSCAPE" -w 18 -h 18 Resources/icon/inline.svg -o Resources/PrismIcon.png 2>/dev/null
"$INKSCAPE" -w 36 -h 36 Resources/icon/inline.svg -o "Resources/PrismIcon@2x.png" 2>/dev/null

echo "Generated Resources/Fauxcus.icns and menu bar PNGs"
