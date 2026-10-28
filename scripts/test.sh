#!/usr/bin/env bash
# Build one app with its unit tests and run them in the simulator.
#
#   scripts/test.sh <app> [device] [test_name]
#   scripts/test.sh field
#   scripts/test.sh field fenix843mm
#
# The simulator must be running (scripts/sim.sh starts it). Output is the
# simulator console: one line per test and a RESULTS table at the end.
set -euo pipefail

APP="${1:?usage: scripts/test.sh <app> [device] [test_name]}"
DEVICE="${2:-fenix8pro47mm}"
TEST_NAME="${3:-}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sdk-env.sh"

cd "$ROOT/apps/$APP"
mkdir -p bin
echo "monkeyc --unit-test -> apps/$APP/bin/$APP-test.prg ($DEVICE)"
set +e
"$SDK/bin/monkeyc" -d "$DEVICE" -f monkey.jungle -o "bin/$APP-test.prg" -y "$KEY" -w -l 3 --unit-test 2>&1 \
    | grep -v "The (:glance) annotation will be ignored"   # expected for Lib's glance-safe modules (CLAUDE.md)
STATUS=${PIPESTATUS[0]}
set -e
[ "$STATUS" -eq 0 ] || exit "$STATUS"

if ! pgrep -f "ConnectIQ.app|simulator" >/dev/null 2>&1; then
    "$SDK/bin/connectiq" &
    sleep 3
fi
"$SDK/bin/monkeydo" "bin/$APP-test.prg" "$DEVICE" -t $TEST_NAME
