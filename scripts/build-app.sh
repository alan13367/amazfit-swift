#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
CONFIG="${1:-debug}"
case "$CONFIG" in debug|release) ;; *) echo 'Usage: scripts/build-app.sh [debug|release]' >&2; exit 2 ;; esac
swift build --configuration "$CONFIG"
BIN="$(swift build --configuration "$CONFIG" --show-bin-path)"
APP="$PWD/.build/Helio.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
install -m 755 "$BIN/Helio" "$APP/Contents/MacOS/Helio"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/Helio.icns "$APP/Contents/Resources/Helio.icns"
codesign --force --sign - --identifier dev.helio.mac "$APP"
# macOS caches app icons by bundle path and modification date. Bump the bundle date and
# re-register it so Finder and the Dock pick up a changed icon.
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true
printf '\nBuilt %s\n' "$APP"
