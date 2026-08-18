#!/usr/bin/env bash
# Capture HarmonyOS device screenshots + layout dumps for visual QA.
# Usage:
#   ./scripts/device-qa.sh status
#   ./scripts/device-qa.sh start
#   ./scripts/device-qa.sh capture <name>     # jpeg + json → .cursor/review-shots/
#   ./scripts/device-qa.sh click <x> <y>
#   ./scripts/device-qa.sh cards [json]       # print dual-column card bounds
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HDC="${HDC:-$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc}"
SHOT="${SHOT:-$ROOT/.cursor/review-shots}"
BUNDLE="${BUNDLE:-com.brian.cursor.mobile}"

mkdir -p "$SHOT"

need_device() {
  local t
  t="$("$HDC" list targets 2>/dev/null | head -1 | tr -d '[:space:]')"
  if [[ -z "$t" || "$t" == "[Empty]" ]]; then
    echo "hdc: no device. ./scripts/wifi-connect.sh status" >&2
    exit 1
  fi
}

cmd="${1:-status}"
case "$cmd" in
  status)
    echo "==> hdc"
    "$HDC" list targets
    echo "==> shots $SHOT"
    ;;
  start)
    need_device
    "$HDC" shell aa start -a EntryAbility -b "$BUNDLE"
    ;;
  capture)
    NAME="${2:?usage: $0 capture <name>}"
    need_device
    "$HDC" shell snapshot_display -f "/data/local/tmp/${NAME}.jpeg"
    "$HDC" file recv "/data/local/tmp/${NAME}.jpeg" "$SHOT/${NAME}.jpeg"
    "$HDC" shell uitest dumpLayout -p "/data/local/tmp/${NAME}.json"
    "$HDC" file recv "/data/local/tmp/${NAME}.json" "$SHOT/${NAME}.json"
    echo "saved $SHOT/${NAME}.jpeg + .json"
    ;;
  click)
    X="${2:?usage: $0 click <x> <y>}"
    Y="${3:?usage: $0 click <x> <y>}"
    need_device
    "$HDC" shell uitest uiInput click "$X" "$Y"
    ;;
  cards)
    JSON="${2:-}"
    if [[ -z "$JSON" ]]; then
      echo "usage: $0 cards <layout.json>" >&2
      exit 1
    fi
    python3 - "$JSON" <<'PY'
import json, re, sys
path = sys.argv[1]
data = json.load(open(path))

def bounds(s):
    if isinstance(s, str):
        m = re.findall(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", s)
        if m:
            x1, y1, x2, y2 = map(int, m[0])
            return x1, y1, x2, y2, x2 - x1, y2 - y1
    return None

root = None
cols = []

def walk(n):
    global root
    if isinstance(n, dict):
        typ = str(n.get("type") or "")
        b = bounds(n.get("bounds"))
        if typ == "root" and b:
            root = b
        if typ == "Column" and b and 400 <= b[4] <= 1000 and 200 <= b[5] <= 400:
            cols.append(b)
        if typ == "NavBar" and b and 500 <= b[4] <= 900:
            print(f"NavBar {b[4]}x{b[5]} x0={b[0]}")
        if typ == "Stack" and b and 120 <= b[5] <= 200 and 400 <= b[4] <= 900:
            print(f"Stack-card {b[4]}x{b[5]} @({b[0]},{b[1]})")
        for v in n.values():
            if isinstance(v, (dict, list)):
                walk(v)
    elif isinstance(n, list):
        for x in n:
            walk(x)

walk(data)
if root:
    print(f"screen {root[4]}x{root[5]}")
seen = set()
for b in cols:
    if b in seen:
        continue
    seen.add(b)
    print(f"Column {b[4]}x{b[5]} @({b[0]},{b[1]})")
PY
    ;;
  *)
    echo "usage: $0 status|start|capture <name>|click <x> <y>|cards <json>" >&2
    exit 1
    ;;
esac
