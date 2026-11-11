#!/bin/zsh
# Takes the Phase 1 design screenshots. Set DRY=1 to check launches without capturing.
cd "$(dirname "$0")/.."
BIN=build/Build/Products/Debug/Remi.app/Contents/MacOS/Remi
OUT=docs/phase1
mkdir -p "$OUT"
HELPER=$(mktemp -d)/window-region
swiftc -O Scripts/window-region.swift -o "$HELPER" || exit 1
shot() {
  local name=$1; shift
  "$BIN" --open --allow-capture "$@" &
  local pid=$!
  sleep 2
  local region=$($HELPER $pid)
  echo "$name region=$region alive=$(kill -0 $pid 2>/dev/null && echo yes || echo no)"
  [[ -z "$DRY" ]] && screencapture -x -R "$region" "$OUT/$name.png"
  kill $pid; wait $pid 2>/dev/null
}
for mode in light dark; do
  for tab in today tasks notes links; do
    shot "edge-comfortable-$tab-$mode" --tab=$tab --appearance=$mode
  done
  shot "edge-compact-today-$mode" --density=compact --appearance=$mode
  shot "tile-comfortable-today-$mode" --handle=tile --appearance=$mode
done
