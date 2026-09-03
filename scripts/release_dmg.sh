#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
APP_DIR="$ROOT_DIR/dist/Signal Monitor.app"
IDENTITY="${SIGNAL_MONITOR_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${SIGNAL_MONITOR_NOTARY_PROFILE:-}"

if [[ -z "$IDENTITY" ]]; then
  print -u2 "Set SIGNAL_MONITOR_SIGN_IDENTITY to a Developer ID Application identity."
  exit 2
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
  print -u2 "Set SIGNAL_MONITOR_NOTARY_PROFILE to a notarytool keychain profile."
  exit 2
fi

"$ROOT_DIR/scripts/package_app.sh"
/usr/bin/codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_DIR"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_DIR/Contents/Info.plist")
DMG="$ROOT_DIR/dist/Signal-Monitor-$VERSION.dmg"
/bin/rm -f "$DMG"
/usr/bin/hdiutil create -volname "Signal Monitor" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG"
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG"
/usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature -v "$DMG"

print "Release ready: $DMG"
