#!/usr/bin/env bash
# One Connect IQ simulator per Mac. It is a single process on one port
# (a second one exits at once), and every session that loads an app into
# it replaces whatever another session was looking at. So claim it, by
# ID, before loading anything, and give it back when done.
#
#   scripts/simlock.sh claim [minutes]   take the simulator (default 10 min); fails if another ID holds it
#   scripts/simlock.sh wait [minutes]    wait until it is free, then claim it
#   scripts/simlock.sh release           give it back (only the holder can)
#   scripts/simlock.sh status            who holds it
#
# The ID is $CIQ_SIM_ID, or the name of this checkout: worktrees have
# different names, so different sessions do too. A claim expires on its
# own, so a session that dies does not hold the simulator forever.
# test.sh claims and releases around a test run; sim.sh claims and keeps
# the claim while the app is on screen.
set -euo pipefail

LOCK="${CIQ_SIM_LOCK:-/tmp/ciq-simulator.lock}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ID="${CIQ_SIM_ID:-$(basename "$ROOT")}"

now() { date +%s; }
when() { date -r "$1" +%H:%M:%S 2>/dev/null || date -d "@$1" +%H:%M:%S; }

# Prints "owner until" when a live claim exists, else fails
holder() {
    [ -f "$LOCK" ] || return 1
    local owner until
    owner="$(sed -n 's/^owner=//p' "$LOCK" | head -1)"
    until="$(sed -n 's/^until=//p' "$LOCK" | head -1)"
    [ -n "$owner" ] && [ -n "$until" ] && [ "$until" -gt "$(now)" ] || return 1
    echo "$owner $until"
}

case "${1:-status}" in
claim)
    MIN="${2:-10}"
    if h="$(holder)" && [ "${h%% *}" != "$ID" ]; then
        echo "simulator held by ${h%% *} until $(when "${h##* }"); try scripts/simlock.sh wait" >&2
        exit 1
    fi
    printf 'owner=%s\nuntil=%s\nsince=%s\n' "$ID" "$(( $(now) + MIN * 60 ))" "$(date +%H:%M:%S)" > "$LOCK"
    echo "simulator claimed by $ID for $MIN min"
    ;;
wait)
    MIN="${2:-10}"
    while h="$(holder)" && [ "${h%% *}" != "$ID" ]; do
        echo "waiting: simulator held by ${h%% *} until $(when "${h##* }")"
        sleep 10
    done
    exec "$0" claim "$MIN"
    ;;
release)
    if h="$(holder)" && [ "${h%% *}" != "$ID" ]; then
        echo "not yours: simulator held by ${h%% *}" >&2
        exit 1
    fi
    rm -f "$LOCK"
    echo "simulator released by $ID"
    ;;
status)
    if h="$(holder)"; then
        echo "held by ${h%% *} until $(when "${h##* }")$( [ "${h%% *}" = "$ID" ] && echo " (that is you)")"
    else
        echo "free"
    fi
    ;;
*)
    sed -n 2,15p "$0"
    exit 1
    ;;
esac
