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
# Stage the app bundle itself, rather than its contents, at the volume root.
STAGING_DIR=$(/usr/bin/mktemp -d "$ROOT_DIR/dist/dmg-stage.XXXXXX")
trap '/bin/rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto "$APP_DIR" "$STAGING_DIR/Signal Monitor.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/hdiutil create -volname "Signal Monitor" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG"
/usr/bin/codesign --force --timestamp --sign "$IDENTITY" "$DMG"
/usr/bin/xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
/usr/bin/xcrun stapler staple "$DMG"
/usr/bin/xcrun stapler validate "$DMG"
/usr/sbin/spctl --assess --type open --context context:primary-signature -v "$DMG"

print "Release ready: $DMG"
