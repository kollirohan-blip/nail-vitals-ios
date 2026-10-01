#!/bin/bash
# Imports scans shared from another phone (the zip from the app's Study
# panel -> "Share saved photos") into captures/imported/<initials>/, and
# prefixes their participant codes (P1 -> <initials>-P1) so another
# phone's P1 never mixes with this one's. The captures folder is ignored
# by git: these are photos of people's hands.
#
#   bash nail-vitals-ios/Tools/import-captures.sh ~/Downloads/NailVitals-....zip AB
#
# Then replay everything, e.g.:
#   photo-lab captures/latest/* captures/imported/*/* --report --out <folder>
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "Usage: $0 <zip from the app> <scanner initials>" >&2
  exit 1
fi
ZIP="$1"
PREFIX=$(echo "$2" | tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9')
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="$ROOT/captures/imported/$PREFIX"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unzip -q "$ZIP" -d "$TMP"
mkdir -p "$DEST"
count=0
skipped=0
while IFS= read -r photo; do
  dir=$(dirname "$photo")
  name=$(basename "$dir")
  if [ -e "$DEST/$name" ]; then
    skipped=$((skipped + 1))
    continue
  fi
  cp -R "$dir" "$DEST/$name"
  if [ -f "$DEST/$name/capture.json" ]; then
    python3 - "$DEST/$name/capture.json" "$PREFIX" <<'PY'
import json, sys
path, prefix = sys.argv[1], sys.argv[2]
with open(path) as f:
    capture = json.load(f)
code = capture.get("participant")
if code and not code.startswith(prefix + "-"):
    capture["participant"] = prefix + "-" + code
with open(path, "w") as f:
    json.dump(capture, f, indent=2, sort_keys=True)
PY
  fi
  count=$((count + 1))
done < <(find "$TMP" -name photo.jpg -not -path "*/__MACOSX/*")

echo "Imported $count captures into $DEST ($skipped already there)."
