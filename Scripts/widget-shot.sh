#!/bin/zsh
# Captures one widget prototype over the desktop: widget-shot.sh <output-name> <app args...>
cd "$(dirname "$0")/.."
BIN=build/Build/Products/Debug/Perch.app/Contents/MacOS/Perch
OUT=docs/phase1
mkdir -p "$OUT"
HELPER=${TMPDIR:-/tmp}/perch-window-region
[[ -x "$HELPER" ]] || swiftc -O Scripts/window-region.swift -o "$HELPER" || exit 1
name=$1; shift
"$BIN" --allow-capture "$@" &
pid=$!
sleep ${SETTLE:-2}
region=$($HELPER $pid)
echo "$name region=$region alive=$(kill -0 $pid 2>/dev/null && echo yes || echo no)"
screencapture -x -R "$region" "$OUT/$name.png"
kill $pid; wait $pid 2>/dev/null
