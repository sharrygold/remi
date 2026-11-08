#!/bin/zsh
# Takes the Phase 1 design screenshots. Set DRY=1 to check launches without capturing.
cd "$(dirname "$0")/.."
BIN=build/Build/Products/Debug/Perch.app/Contents/MacOS/Perch
OUT=docs/phase1
mkdir -p "$OUT"
shot() {
  local name=$1; shift
  "$BIN" --open --allow-capture "$@" &
  local pid=$!
  sleep 2
  local region=$(swift Scripts/window-region.swift $pid)
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
