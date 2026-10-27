#!/usr/bin/env bash
# Start the simulator (if needed) and load an app into it.
#
#   scripts/sim.sh <app> [device]
#
# In the simulator: Settings > Low Power Mode shows the always-on layout,
# File > View Memory shows peak memory, and Settings > Display > Burn-In
# Protection checks the 10 % rule.
set -euo pipefail

APP="${1:?usage: scripts/sim.sh <app> [device]}"
DEVICE="${2:-fenix8pro47mm}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sdk-env.sh"

PRG="$ROOT/apps/$APP/bin/$APP.prg"
[ -f "$PRG" ] || "$ROOT/scripts/build.sh" "$APP" "$DEVICE"

if ! pgrep -f "ConnectIQ.app|simulator" >/dev/null 2>&1; then
    "$SDK/bin/connectiq" &
    sleep 3
fi
"$SDK/bin/monkeydo" "$PRG" "$DEVICE"
