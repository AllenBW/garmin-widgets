#!/usr/bin/env bash
# Capture an app's sample build on the simulator: this worktree's private
# one when scripts/simprivate.sh has started it (no lock), else the shared one.
#
#   .claude/skills/watch-face-review/scripts/sim-shot.sh <app> <out.png> [device]
#
# Claims /tmp/ciq-simulator.lock (waits up to 10 minutes on another
# owner's live claim), builds the sample build (sample.jungle, if the app
# has one) for the device, loads it, waits for it to draw, captures the
# simulator window to <out.png> and a crop of the watch to <out>-crop.png,
# rebuilds the normal build and releases the lock. Needs the sandbox off
# (window list, screen capture) and Pillow for the crop (PYTHON, default
# python3).
set -euo pipefail

APP="${1:?usage: sim-shot.sh <app> <out.png> [device]}"
OUT="${2:?usage: sim-shot.sh <app> <out.png> [device]}"
DEVICE="${3:-fenix847mm}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
LOCK=/tmp/ciq-simulator.lock
ME="${CIQ_SIM_ID:-$(basename "$ROOT")}"
PY="${PYTHON:-python3}"
source "$ROOT/scripts/sdk-env.sh"

PORT="$("$ROOT/scripts/simprivate.sh" port 2>/dev/null || true)"
SIMPID="$("$ROOT/scripts/simprivate.sh" pid 2>/dev/null || true)"

# Wait on someone else's live claim, then claim for 10 minutes (shared only)
for _ in $(seq 60); do
    [ -n "$PORT" ] && break
    if [ -f "$LOCK" ] && ! grep -q "owner=$ME" "$LOCK" && [ "$(grep until "$LOCK" | cut -d= -f2)" -gt "$(date +%s)" ]; then
        sleep 10
    else
        break
    fi
done
if [ -z "$PORT" ]; then
    printf "owner=%s\nuntil=%s\n" "$ME" $(($(date +%s) + 600)) > "$LOCK"
    trap 'grep -q "owner=$ME" "$LOCK" 2>/dev/null && rm -f "$LOCK"' EXIT
fi

JUNGLE="monkey.jungle"
[ -f "$ROOT/apps/$APP/sample.jungle" ] && JUNGLE="monkey.jungle;sample.jungle"
CIQ_JUNGLE="$JUNGLE" "$ROOT/scripts/build.sh" "$APP" "$DEVICE" >/dev/null
cp "$ROOT/apps/$APP/bin/$APP.prg" "$ROOT/apps/$APP/bin/$APP-shot.prg"
"$ROOT/scripts/build.sh" "$APP" "$DEVICE" >/dev/null

if [ -z "$PORT" ]; then
    pgrep -f "[C]onnectIQ.app/Contents/MacOS" >/dev/null || { "$SDK/bin/connectiq" >/dev/null 2>&1 & sleep 14; }
fi
if [ -n "$PORT" ]; then
    (cd "$ROOT/apps/$APP" && timeout 15 "$ROOT/scripts/simprivate.sh" do "bin/$APP-shot.prg" "$DEVICE" >/dev/null 2>&1 || true)
else
    (cd "$ROOT/apps/$APP" && timeout 15 "$SDK/bin/monkeydo" "bin/$APP-shot.prg" "$DEVICE" >/dev/null 2>&1 || true)
fi
sleep 6   # a face that fills a bitmap over several frames needs a moment

[ -x "$HERE/windows" ] || swiftc "$HERE/windows.swift" -o "$HERE/windows" 2>/dev/null
for ID in $("$HERE/windows" $SIMPID); do
    screencapture -x -o -l "$ID" "$OUT" 2>/dev/null && break
done
[ -f "$OUT" ] || { echo "no simulator window captured" >&2; exit 1; }
"$PY" -I -c "
import sys
from PIL import Image
im = Image.open(sys.argv[1]); w, h = im.size
im.crop((int(w * 0.13), int(h * 0.205), int(w * 0.87), int(h * 0.745))).save(sys.argv[2])
" "$OUT" "${OUT%.png}-crop.png"
echo "$OUT"
