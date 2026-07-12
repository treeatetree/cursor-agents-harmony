#!/usr/bin/env bash
# Connect HarmonyOS phone for debugging
set -euo pipefail

HDC="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}/default/openharmony/toolchains/hdc"

echo "1) Phone: Settings → About → tap Build number 7 times to enable Developer options"
echo "2) Developer options → enable USB debugging (and 'USB debugging (Security settings)' if present)"
echo "3) Connect USB (or pair wireless debugging), accept the trust prompt on phone"
echo ""
echo "Running: $HDC list targets"
"$HDC" start 2>/dev/null || true
"$HDC" list targets
echo ""
echo "If still Empty:"
echo "  - Try another cable/port"
echo "  - Wireless: Developer options → Wireless debugging → Pair with pairing code"
echo "    then: hdc tconn <ip>:<port>"
