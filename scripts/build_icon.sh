#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="$ROOT_DIR/Resources/AppIcon.svg"
ICONSET="$ROOT_DIR/.build/SignalMonitor.iconset"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$ICONSET"

render_png() {
    local size="$1"
    local output="$2"

    if command -v rsvg-convert >/dev/null 2>&1; then
        local rendered="${output}.rendered.png"
        rsvg-convert -w "$size" -h "$size" "$SOURCE" -o "$rendered"
        sips -s format png "$rendered" --out "$output" >/dev/null
        rm "$rendered"
    else
        sips -s format png -z "$size" "$size" "$SOURCE" --out "$output" >/dev/null
    fi
}

for size in 16 32 128 256 512; do
    render_png "$size" "$ICONSET/icon_${size}x${size}.png"
    double=$((size * 2))
    render_png "$double" "$ICONSET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$OUTPUT"
print "$OUTPUT"
