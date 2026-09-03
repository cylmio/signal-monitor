#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
SOURCE="$ROOT_DIR/Resources/AppIcon.svg"
ICONSET="$ROOT_DIR/.build/SignalMonitor.iconset"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"

mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -s format png -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$OUTPUT"
print "$OUTPUT"
