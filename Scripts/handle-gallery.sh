#!/bin/zsh
# Captures every handle design over the real desktop, in light and dark.
cd "$(dirname "$0")/.."
BIN=build/Build/Products/Debug/Perch.app/Contents/MacOS/Perch
OUT=docs/phase1
mkdir -p "$OUT"
HELPER=$(mktemp -d)/window-region
swiftc -O Scripts/window-region.swift -o "$HELPER" || exit 1
for mode in light dark; do
  "$BIN" --gallery --allow-capture --appearance=$mode &
  pid=$!
  sleep 2
  region=$($HELPER $pid)
  echo "$mode region=$region"
  screencapture -x -R "$region" "$OUT/handles-$mode.png"
  kill $pid; wait $pid 2>/dev/null
done
