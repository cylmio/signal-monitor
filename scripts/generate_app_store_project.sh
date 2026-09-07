#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
GENERATOR_DIR="$ROOT_DIR/AppStore/Generated"

/opt/homebrew/bin/cmake \
  -S "$ROOT_DIR/AppStore" \
  -B "$GENERATOR_DIR" \
  -G Xcode

print "Generated: $GENERATOR_DIR/SignalMonitorAppStore.xcodeproj"
