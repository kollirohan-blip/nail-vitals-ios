#!/bin/bash
# Copies the app's saved captures (Documents/Captures) off the USB-connected
# iPhone into a local folder (default: ./captures). Then replay them with:
#   photo-lab/photo-lab captures/* --out annotated
set -euo pipefail

DEST="${1:-captures}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/sowjanyakolli/Downloads/rohan-hosa-project1/Xcode 2.app/Contents/Developer}"

# The phone lists as "connected" or "available (paired)" depending on state.
DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E ' (connected|available)' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1 || true)
if [ -z "$DEVICE" ]; then
    echo "No connected iPhone found. Plug it in and unlock it." >&2
    exit 1
fi

mkdir -p "$DEST"
xcrun devicectl device copy from --device "$DEVICE" \
    --domain-type appDataContainer --domain-identifier com.Rohankolli.NailVitals \
    --source Documents/Captures --destination "$DEST"
