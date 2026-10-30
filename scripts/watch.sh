#!/usr/bin/env bash
# Sideload to a watch over USB (MTP) and pull its logs back, with libmtp
# (`brew install libmtp`). The watch must be in MTP mode (hold Up/Menu →
# Watch Settings → System → Advanced → USB Mode → MTP) and nothing else may
# hold the connection (quit Garmin Express and OpenMTP).
#
#   scripts/watch.sh queue [dir ...]       build every app in apps/ (and in each extra
#                                          checkout given) into watch-queue/, newest copy wins
#   scripts/watch.sh flush                 copy the whole queue onto the watch, then empty it
#   scripts/watch.sh push <app> [device]   build and copy one app onto the watch now
#   scripts/watch.sh ls                    list GARMIN/Apps and GARMIN/Apps/LOGS
#   scripts/watch.sh logs [dir]            download GARMIN/Apps/LOGS/* (default watch-logs/)
#   scripts/watch.sh rm <NAME.PRG|NAME.TXT> delete one file from Apps or Apps/LOGS
#
# The watch installs a .prg from GARMIN/Apps when the USB session ends, so
# unplug after a push or a flush. println output goes to
# GARMIN/Apps/LOGS/<NAME>.TXT, which push creates, and crashes to
# CIQ_LOG.YML in the same folder. The default device is the watch on the
# desk; override with CIQ_WATCH_DEVICE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_DEFAULT="${CIQ_WATCH_DEVICE:-fenix847mm}"
APPS_PATH="/GARMIN/Apps"
LOGS_PATH="/GARMIN/Apps/LOGS"
QUEUE="$ROOT/watch-queue"

for tool in mtp-files mtp-sendfile mtp-getfile mtp-delfile; do
    command -v "$tool" >/dev/null || { echo "$tool not found: brew install libmtp" >&2; exit 1; }
done

# After a plug-in the watch spends about ten seconds in Garmin's own USB
# protocol (product id 3) before it switches to MTP (product id 0x51b8), so
# wait for the switch rather than failing on the first listing.
wait_for_mtp() {
    local n=0
    until ioreg -p IOUSB -l -w0 2>/dev/null | grep -q '"idProduct" = 20920' || [ "$n" -ge 20 ]; do
        if ! ioreg -p IOUSB -l -w0 2>/dev/null | grep -q '"idVendor" = 2334'; then
            echo "no Garmin watch on USB: plug it in" >&2; exit 1
        fi
        [ "$n" -eq 0 ] && echo "waiting for the watch to switch to MTP..."
        sleep 3; n=$((n + 1))
    done
    if [ "$n" -ge 20 ]; then
        echo "the watch stayed in Garmin USB mode: set USB Mode to MTP (hold UP, Watch Settings, System, Advanced) and replug" >&2
        exit 1
    fi
}

# Print "id<TAB>parent<TAB>name<TAB>size" for every file on the watch.
listing() {
    mtp-files 2>/dev/null | grep -v "extended association" | python3 -I -c '
import sys, re
recs, cur = [], {}
for line in sys.stdin:
    m = re.match(r"File ID: (\d+)", line)
    if m:
        if cur: recs.append(cur)
        cur = {"id": m.group(1)}
        continue
    for key, pat in (("name", r"\s*Filename: (.*)"), ("size", r"\s*File size (\d+)"), ("parent", r"\s*Parent ID: (\d+)")):
        m = re.match(pat, line)
        if m and cur: cur[key] = m.group(1).rstrip()
if cur: recs.append(cur)
for r in recs:
    print("\t".join((r["id"], r.get("parent", "?"), r.get("name", "?"), r.get("size", "?"))))
'
}

# Folder ids for Apps and LOGS from mtp-folders ("<id><TAB><indent><name>").
folder_ids() {
    mtp-folders 2>/dev/null | grep -v "extended association" | python3 -I -c '
import sys, re
stack = []  # (depth, name, id)
apps = logs = None
for line in sys.stdin:
    m = re.match(r"(\d+)\t( *)(.*)$", line.rstrip("\n"))
    if not m: continue
    fid, depth, name = m.group(1), len(m.group(2)) // 2, m.group(3)
    while stack and stack[-1][0] >= depth: stack.pop()
    path = "/" + "/".join([s[1] for s in stack] + [name])
    stack.append((depth, name, fid))
    if path.lower() == "/garmin/apps": apps = fid
    if path.lower() == "/garmin/apps/logs": logs = fid
print(apps or "", logs or "")
'
}

show() {
    read -r APPS LOGS < <(folder_ids)
    [ -n "$APPS" ] && [ -n "$LOGS" ] || { echo "GARMIN/Apps or GARMIN/Apps/LOGS not found on the watch" >&2; exit 1; }
    listing | awk -F'\t' -v a="$APPS" -v l="$LOGS" '$2==a{printf "Apps  %-18s %8s bytes  id %s\n",$3,$4,$1} $2==l{printf "LOGS  %-18s %8s bytes  id %s\n",$3,$4,$1}'
}

# Build one app from one checkout into a folder as NAME.PRG, with its empty NAME.TXT
build_into() {
    local checkout="$1" app="$2" device="$3" dest="$4"
    local name; name="$(echo "$app" | tr '[:lower:]' '[:upper:]')"
    source "$ROOT/scripts/sdk-env.sh"
    mkdir -p "$dest/LOGS"
    ( cd "$checkout/apps/$app" && "$SDK/bin/monkeyc" -d "$device" -f monkey.jungle -o "$dest/$name.PRG" -y "$KEY" -w 2>&1 \
        | grep -v "The (:glance) annotation will be ignored" ; exit "${PIPESTATUS[0]}" ) || return 1
    printf '\n' > "$dest/LOGS/$name.TXT"
    rm -rf "$dest/gen" "$dest/internal-mir" "$dest/external-mir" "$dest/$name.PRG.debug.xml"
    echo "queued $name.PRG ($(stat -f %z "$dest/$name.PRG") bytes) from $checkout"
}

# Send a file to a folder on the watch, replacing an earlier copy by name
send() {
    local src="$1" folder="$2" name; name="$(basename "$src")"
    show | awk -v n="$name" '$2==n{print $NF}' | while read -r id; do
        mtp-delfile "$id" >/dev/null 2>&1 || true
    done
    mtp-sendfile "$src" "$folder" 2>&1 | grep -v "extended association" | grep -E "skipping|rror" || true
}

case "${1:-}" in
queue)
    shift
    DEVICE="$DEVICE_DEFAULT"
    DEST="$QUEUE/$DEVICE"
    mkdir -p "$DEST/LOGS"
    # this checkout first, so its versions win over older copies elsewhere
    for dir in "$ROOT/apps"/*/; do
        app="$(basename "$dir")"
        [ -f "$dir/monkey.jungle" ] || continue
        build_into "$ROOT" "$app" "$DEVICE" "$DEST" || { echo "build failed: $app" >&2; exit 1; }
    done
    for extra in "$@"; do
        extra="${extra%/}"
        [ -d "$extra/apps" ] || extra="$(dirname "$extra")"
        for dir in "$extra/apps"/*/; do
            app="$(basename "$dir")"
            [ -f "$dir/monkey.jungle" ] || continue
            if [ -d "$ROOT/apps/$app" ]; then
                echo "skipped $app from $extra: this checkout has it"
                continue
            fi
            build_into "$extra" "$app" "$DEVICE" "$DEST" || { echo "build failed: $app in $extra" >&2; exit 1; }
        done
    done
    echo "queue for $DEVICE: $(ls "$DEST"/*.PRG | wc -l | tr -d ' ') apps in $DEST; scripts/watch.sh flush copies them when the watch is on the cable"
    ;;
flush)
    DEVICE="$DEVICE_DEFAULT"
    DEST="$QUEUE/$DEVICE"
    ls "$DEST"/*.PRG >/dev/null 2>&1 || { echo "nothing queued for $DEVICE: scripts/watch.sh queue first" >&2; exit 1; }
    wait_for_mtp
    for prg in "$DEST"/*.PRG; do
        name="$(basename "$prg" .PRG)"
        echo "sending $name.PRG"
        send "$prg" "$APPS_PATH"
        send "$DEST/LOGS/$name.TXT" "$LOGS_PATH"
    done
    echo "--- on the watch now:"
    show | grep -E "\.PRG" || true
    rm -rf "$DEST"
    echo "queue emptied. Unplug the watch to let it install everything."
    ;;
push)
    APP="${2:?usage: scripts/watch.sh push <app> [device]}"
    DEVICE="${3:-$DEVICE_DEFAULT}"
    NAME="$(echo "$APP" | tr '[:lower:]' '[:upper:]')"
    "$ROOT/scripts/build.sh" "$APP" "$DEVICE"
    STAGE="$(mktemp -d)"
    cp "$ROOT/apps/$APP/bin/$APP.prg" "$STAGE/$NAME.PRG"
    printf '\n' > "$STAGE/$NAME.TXT"
    wait_for_mtp
    send "$STAGE/$NAME.PRG" "$APPS_PATH"
    send "$STAGE/$NAME.TXT" "$LOGS_PATH"
    rm -rf "$STAGE"
    show | grep -E "$NAME\.(PRG|TXT)" || { echo "push failed: $NAME not listed" >&2; exit 1; }
    echo "Unplug the watch to let it install $NAME.PRG."
    ;;
ls)
    wait_for_mtp
    show
    ;;
logs)
    OUT="${2:-$ROOT/watch-logs}"
    mkdir -p "$OUT"
    wait_for_mtp
    read -r APPS LOGS < <(folder_ids)
    listing | awk -F'\t' -v l="$LOGS" '$2==l{print $1"\t"$3}' | while IFS=$'\t' read -r id name; do
        mtp-getfile "$id" "$OUT/$name" >/dev/null 2>&1 && echo "$OUT/$name ($(stat -f %z "$OUT/$name") bytes)" || echo "failed: $name"
    done
    ;;
rm)
    NAME="${2:?usage: scripts/watch.sh rm <NAME.PRG|NAME.TXT>}"
    wait_for_mtp
    show | awk -v n="$NAME" '$2==n{print $NF}' | while read -r id; do mtp-delfile "$id" >/dev/null 2>&1 && echo "deleted $NAME ($id)"; done
    ;;
*)
    sed -n 2,20p "$0"; exit 1 ;;
esac
