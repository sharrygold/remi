#!/bin/zsh
# Builds a Release copy and installs it in /Applications (or ~/Applications if that isn't writable),
# replacing any copy already there. Your data is not touched: it lives in Application Support.
set -e
cd "$(dirname "$0")/.."
NAME=$(awk '/APP_DISPLAY_NAME:/ {print $2}' project.yml)
echo "Building $NAME (Release)…"
xcodegen generate -q
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release -derivedDataPath build/release -allowProvisioningUpdates build -quiet
APP="build/release/Build/Products/Release/$NAME.app"
DEST=/Applications
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
mkdir -p "$DEST"
echo "Closing any running copy…"
pkill -x "$NAME" 2>/dev/null || true
sleep 1
rm -rf "$DEST/$NAME.app"
cp -R "$APP" "$DEST/"
open "$DEST/$NAME.app"
echo "Installed $DEST/$NAME.app and opened it."
echo "Turn on Settings > General > Open at login so it starts with your Mac."
