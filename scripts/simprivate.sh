#!/usr/bin/env bash
# A Connect IQ simulator of this worktree's own, beside the shared one, so a
# session can test and capture without waiting on scripts/simlock.sh.
#
#   scripts/simprivate.sh start     # start it (if it isn't running); prints its port
#   scripts/simprivate.sh port      # its port, or nothing (exit 1) when it isn't running
#   scripts/simprivate.sh pid       # its process id, likewise
#   scripts/simprivate.sh stop      # quit it
#   scripts/simprivate.sh do <prg> <device> [-t [test]]   # monkeydo, on it
#
# While it runs, scripts/test.sh and the review skill's sim-shot.sh use it
# instead of the shared simulator, and skip the lock.
#
# How: the simulator allows one instance per home folder (a lock file,
# ~/Sim-<user>), keeps the watch's storage under $TMPDIR/com.garmin.connectiq,
# and listens on $SHELL_SERVER_PORT (1234 by default). So this one gets its own home (linking back only the
# Garmin folders: SDKs, devices, fonts, the developer key), its own TMPDIR,
# its own port, and its own copy of the app under another program name. monkeydo itself ignores $SHELL_SERVER_PORT: it tries
# ports 1234 to 1238 and takes the first that answers, which is the shared
# simulator. So `do` runs monkeydo's Java with a shell of our own
# (scripts/simprivate-shell) that connects to this simulator's port
# whatever port it is handed, and refuses to run without one. Never call
# the SDK's monkeydo for the private simulator. Needs the sandbox off (it
# opens a window).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ME="${CIQ_SIM_ID:-$(basename "$ROOT")}"
DIR="${CIQ_PRIVATE_DIR:-/tmp/ciq-private-$ME}"
source "$ROOT/scripts/sdk-env.sh"

running() {
    [ -f "$DIR/pid" ] && kill -0 "$(cat "$DIR/pid")" 2>/dev/null
}

case "${1:-}" in
    start)
        if running; then
            cat "$DIR/port"
            exit 0
        fi
        mkdir -p "$DIR/home/Library/Application Support" "$DIR/tmp"
        ln -sfn "$HOME/Library/Application Support/Garmin" "$DIR/home/Library/Application Support/Garmin"
        ln -sfn "$HOME/.garmin" "$DIR/home/.garmin"
        # the first free port from 1241
        PORT=1241
        while lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; do
            PORT=$((PORT + 1))
        done
        # a copy of the app with its program renamed, so that restarting the
        # shared simulator by name (killall simulator, pkill -f ConnectIQ.app)
        # leaves this one running. It sits in a folder that mirrors the SDK's
        # bin (links to everything else there), since it reads version.txt
        # and the like from beside itself.
        APP="$DIR/bin/CIQPrivate.app"
        if [ "$(cat "$DIR/sdk" 2>/dev/null)" != "$SDK" ] || [ ! -x "$APP/Contents/MacOS/ciqprivate" ]; then
            rm -rf "$DIR/bin" "$DIR/CIQPrivate.app"
            mkdir -p "$DIR/bin"
            for f in "$SDK/bin/"*; do
                [ "$(basename "$f")" = "ConnectIQ.app" ] || ln -s "$f" "$DIR/bin/$(basename "$f")"
            done
            cp -R "$SDK/bin/ConnectIQ.app" "$APP"
            mv "$APP/Contents/MacOS/simulator" "$APP/Contents/MacOS/ciqprivate"
            plutil -replace CFBundleExecutable -string ciqprivate "$APP/Contents/Info.plist"
            codesign --force --deep --sign - "$APP" 2>/dev/null   # an edited bundle must be re-signed to run
            echo "$SDK" >"$DIR/sdk"
        fi
        (cd "$DIR/tmp" && HOME="$DIR/home" TMPDIR="$DIR/tmp/" SHELL_SERVER_PORT="$PORT" \
            exec nohup "$APP/Contents/MacOS/ciqprivate" >"$DIR/log" 2>&1) &
        echo $! >"$DIR/pid"
        echo "$PORT" >"$DIR/port"
        for _ in $(seq 30); do
            lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 && break
            sleep 1
        done
        running || { echo "the private simulator didn't start; see $DIR/log" >&2; exit 1; }
        echo "$PORT"
        ;;
    port)
        running && cat "$DIR/port" || exit 1
        ;;
    pid)
        running && cat "$DIR/pid" || exit 1
        ;;
    do)
        running || { echo "the private simulator isn't running: scripts/simprivate.sh start" >&2; exit 1; }
        shift
        PRG="${1:?usage: simprivate.sh do <prg> <device> [-t [test]]}"
        DEVICE="${2:?usage: simprivate.sh do <prg> <device> [-t [test]]}"
        shift 2
        CIQ_PRIVATE_PORT="$(cat "$DIR/port")" exec java -classpath "$SDK/bin/monkeybrains.jar" \
            com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux -f "$PRG" -d "$DEVICE" \
            -s "$ROOT/scripts/simprivate-shell" "$@"
        ;;
    stop)
        if running; then
            kill "$(cat "$DIR/pid")"
        fi
        rm -f "$DIR/pid" "$DIR/port"
        ;;
    *)
        echo "usage: scripts/simprivate.sh start|port|pid|stop|do" >&2
        exit 2
        ;;
esac
