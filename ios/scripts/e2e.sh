#!/usr/bin/env bash
# Runs the end-to-end UI test on a Simulator and exports its screenshots to ios/e2e-artifacts/<appearance>/.
# Usage: scripts/e2e.sh [dark|light] [simulator name]   (defaults: dark, "iPhone 18 Pro")
set -euo pipefail
cd "$(dirname "$0")/.."
appearance="${1:-dark}"
device="${2:-iPhone 18 Pro}"
udid=$(xcrun simctl list devices available | grep -F "$device (" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl ui "$udid" appearance "$appearance"
result="/tmp/archy-e2e-$appearance.xcresult"
rm -rf "$result"
xcodebuild test -project Archy.xcodeproj -scheme Archy -destination "id=$udid" \
  -derivedDataPath /tmp/ArchyDD-e2e -resultBundlePath "$result" -quiet
out="e2e-artifacts/$appearance"
rm -rf "$out" && mkdir -p "$out"
xcrun xcresulttool export attachments --path "$result" --output-path "$out" >/dev/null
# Name files after their attachment names (01-welcome.png, ...).
python3 -I - "$out" <<'PY'
import json, os, sys
out = sys.argv[1]
for test in json.load(open(os.path.join(out, "manifest.json"))):
    for a in test.get("attachments", []):
        src = os.path.join(out, a["exportedFileName"])
        name = a.get("suggestedHumanReadableName", a["exportedFileName"]).split("_")[0]
        os.rename(src, os.path.join(out, name + ".png"))
os.remove(os.path.join(out, "manifest.json"))
PY
ls "$out"
