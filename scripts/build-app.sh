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
printf '\nBuilt %s\n' "$APP"
