#!/usr/bin/env bash
# Export store packages (.iq: one binary per device in the manifest) for
# the Connect IQ Store, signed with the developer key.
#
#   scripts/package.sh              every app in apps/
#   scripts/package.sh forage sauna just these
#
# Output: dist/<app>.iq (gitignored). Upload each at
# https://apps.garmin.com/developer/upload. Keep the key that signed the
# first upload: a store app can only be updated with the same key.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sdk-env.sh"

APPS=("$@")
if [ ${#APPS[@]} -eq 0 ]; then
    for dir in "$ROOT"/apps/*/; do
        APPS+=("$(basename "$dir")")
    done
fi

mkdir -p "$ROOT/dist"
for app in "${APPS[@]}"; do
    echo "monkeyc -e -> dist/$app.iq"
    rm -f "$ROOT/dist/$app.iq"
    (cd "$ROOT/apps/$app" && "$SDK/bin/monkeyc" -e -r -w -f monkey.jungle -o "$ROOT/dist/$app.iq" -y "$KEY" 2>&1 \
        | grep -v "The (:glance) annotation will be ignored" || true)
    [ -f "$ROOT/dist/$app.iq" ] || { echo "no package for $app" >&2; exit 1; }
done
