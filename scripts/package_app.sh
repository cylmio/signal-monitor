#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/Signal Monitor.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

swift build --package-path "$ROOT_DIR" -c release --arch arm64 --arch x86_64
"$ROOT_DIR/scripts/build_icon.sh"
/bin/rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$ROOT_DIR/.build/apple/Products/Release/SignalMonitor" "$MACOS_DIR/SignalMonitor"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/scripts/desktop_status_bridge.mjs" "$RESOURCES_DIR/desktop_status_bridge.mjs"
cp "$ROOT_DIR/scripts/rollout_status.mjs" "$RESOURCES_DIR/rollout_status.mjs"
cp "$ROOT_DIR/scripts/approval_status.mjs" "$RESOURCES_DIR/approval_status.mjs"
cp "$ROOT_DIR/hooks/signal_monitor_hook.py" "$RESOURCES_DIR/signal_monitor_hook.py"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/Resources/PrivacyInfo.xcprivacy" "$RESOURCES_DIR/PrivacyInfo.xcprivacy"
chmod 755 "$MACOS_DIR/SignalMonitor" "$RESOURCES_DIR/desktop_status_bridge.mjs" "$RESOURCES_DIR/signal_monitor_hook.py"
codesign --force --sign - "$APP_DIR"

print "Built: $APP_DIR"
