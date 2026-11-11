#!/bin/zsh
# One screenshot of the app with demo data, without taking the keyboard.
# Usage: Scripts/shot.sh OUTPUT.png [app arguments…]
cd "$(dirname "$0")/.."
NAME=$(awk '/APP_DISPLAY_NAME:/ {print $2}' project.yml)
BIN="build/debug/Build/Products/Debug/$NAME.app/Contents/MacOS/$NAME"
OUT=$1; shift
mkdir -p "$(dirname "$OUT")"
HELPER=build/window-region
[[ -x $HELPER ]] || swiftc -O Scripts/window-region.swift -o "$HELPER" || exit 1
"$BIN" --allow-capture --no-focus --demo-data "$@" &
PID=$!
sleep ${WAIT:-3.5}
REGION=$($HELPER $PID)
screencapture -x -R "$REGION" "$OUT"
kill $PID; wait $PID 2>/dev/null
echo "$OUT region=$REGION"
