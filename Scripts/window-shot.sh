#!/bin/zsh
# Captures one window of the app alone, with its shadow off and a transparent background.
# Usage: Scripts/window-shot.sh OUTPUT.png [app arguments…]   (WAIT=seconds, PICK=largest|smallest)
cd "$(dirname "$0")/.."
NAME=$(awk '/APP_DISPLAY_NAME:/ {print $2}' project.yml)
BIN="build/debug/Build/Products/Debug/$NAME.app/Contents/MacOS/$NAME"
OUT=$1; shift
mkdir -p "$(dirname "$OUT")"
HELPER=build/window-ids
[[ -x $HELPER && $HELPER -nt Scripts/window-ids.swift ]] || swiftc -O Scripts/window-ids.swift -o "$HELPER" || exit 1
"$BIN" --allow-capture --no-focus --demo-data "$@" &
PID=$!
sleep ${WAIT:-3.5}
LIST=$($HELPER $PID | sort -t' ' -k2 -n)
if [[ ${PICK:-largest} == smallest ]]; then ID=$(echo "$LIST" | head -1 | cut -d' ' -f1); else ID=$(echo "$LIST" | tail -1 | cut -d' ' -f1); fi
screencapture -x -o ${SHADOW:+} -l "$ID" "$OUT"
kill $PID; wait $PID 2>/dev/null
echo "$OUT windows=[$(echo $LIST | tr '\n' ' ')] picked=$ID"
