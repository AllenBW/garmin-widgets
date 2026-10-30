#!/usr/bin/env bash
# Build one app for one device with the SDK the SDK Manager marked current.
#
#   scripts/build.sh <app> [device] [extra monkeyc args]
#   scripts/build.sh field
#   scripts/build.sh field fenix8pro47mm --release
#   CIQ_JUNGLE="monkey.jungle;sample.jungle" scripts/build.sh strata fenix847mm
#
# CIQ_JUNGLE lists the jungle files, default monkey.jungle.
# Output: apps/<app>/bin/<app>.prg. The developer key is read from
# $CIQ_DEVELOPER_KEY, default ~/.garmin/developer_key.der (see README).
set -euo pipefail

APP="${1:?usage: scripts/build.sh <app> [device] [monkeyc args]}"
shift
DEVICE="fenix8pro47mm"
if [ $# -ge 1 ] && [ "${1#-}" = "$1" ]; then
    DEVICE="$1"
    shift
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sdk-env.sh"

cd "$ROOT/apps/$APP"
mkdir -p bin
echo "monkeyc $(cat "$SDK/bin/version.txt") -> apps/$APP/bin/$APP.prg ($DEVICE)"
# Lib's glance-safe modules carry (:glance); in a watch face monkeyc warns that
# the annotation is ignored (CLAUDE.md). That one expected line is dropped.
set +e
"$SDK/bin/monkeyc" -d "$DEVICE" -f "${CIQ_JUNGLE:-monkey.jungle}" -o "bin/$APP.prg" -y "$KEY" -w "$@" 2>&1 \
    | grep -v "The (:glance) annotation will be ignored"
STATUS=${PIPESTATUS[0]}
set -e
exit "$STATUS"
