#!/usr/bin/env bash
# Sideload to a watch over USB (MTP) and pull its logs back, with libmtp
# (`brew install libmtp`). The watch must be in MTP mode (hold Up/Menu →
# Watch Settings → System → Advanced → USB Mode → MTP) and nothing else may
# hold the connection (quit Garmin Express and OpenMTP).
#
#   scripts/watch.sh push <app> [device]   build and copy apps/<app> onto the watch
#   scripts/watch.sh ls                    list GARMIN/Apps and GARMIN/Apps/LOGS
#   scripts/watch.sh logs [dir]            download GARMIN/Apps/LOGS/* (default watch-logs/)
#   scripts/watch.sh rm <NAME.PRG|NAME.TXT> delete one file from Apps or Apps/LOGS
#
# The watch installs a .prg from GARMIN/Apps when the USB session ends, so
# unplug after a push. println output goes to GARMIN/Apps/LOGS/<NAME>.TXT,
# which push creates, and crashes to CIQ_LOG.YML in the same folder. The
# default device is the watch on the desk; override with CIQ_WATCH_DEVICE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVICE_DEFAULT="${CIQ_WATCH_DEVICE:-fenix847mm}"
APPS_PATH="/GARMIN/Apps"
LOGS_PATH="/GARMIN/Apps/LOGS"

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
wait_for_mtp

# Print "id<TAB>folder<TAB>name<TAB>size" for every file in Apps or LOGS.
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

case "${1:-}" in
push)
    APP="${2:?usage: scripts/watch.sh push <app> [device]}"
    DEVICE="${3:-$DEVICE_DEFAULT}"
    NAME="$(echo "$APP" | tr '[:lower:]' '[:upper:]')"
    "$ROOT/scripts/build.sh" "$APP" "$DEVICE"
    STAGE="$(mktemp -d)"
    cp "$ROOT/apps/$APP/bin/$APP.prg" "$STAGE/$NAME.PRG"
    printf '\n' > "$STAGE/$NAME.TXT"
    # Replace an earlier copy: the watch keeps the old object otherwise.
    show | awk -v n="$NAME.PRG" -v t="$NAME.TXT" '$2==n||$2==t{print $NF}' | while read -r id; do
        echo "removing old object $id"; mtp-delfile "$id" >/dev/null 2>&1 || true
    done
    mtp-sendfile "$STAGE/$NAME.PRG" "$APPS_PATH" 2>&1 | grep -v "extended association" | grep -E "Sending|skipping|rror" || true
    mtp-sendfile "$STAGE/$NAME.TXT" "$LOGS_PATH" 2>&1 | grep -v "extended association" | grep -E "Sending|skipping|rror" || true
    rm -rf "$STAGE"
    show | grep -E "$NAME\.(PRG|TXT)" || { echo "push failed: $NAME not listed" >&2; exit 1; }
    echo "Unplug the watch to let it install $NAME.PRG."
    ;;
ls)
    show
    ;;
logs)
    OUT="${2:-$ROOT/watch-logs}"
    mkdir -p "$OUT"
    read -r APPS LOGS < <(folder_ids)
    listing | awk -F'\t' -v l="$LOGS" '$2==l{print $1"\t"$3}' | while IFS=$'\t' read -r id name; do
        mtp-getfile "$id" "$OUT/$name" >/dev/null 2>&1 && echo "$OUT/$name ($(stat -f %z "$OUT/$name") bytes)" || echo "failed: $name"
    done
    ;;
rm)
    NAME="${2:?usage: scripts/watch.sh rm <NAME.PRG|NAME.TXT>}"
    show | awk -v n="$NAME" '$2==n{print $NF}' | while read -r id; do mtp-delfile "$id" >/dev/null 2>&1 && echo "deleted $NAME ($id)"; done
    ;;
*)
    sed -n 2,16p "$0"; exit 1 ;;
esac
