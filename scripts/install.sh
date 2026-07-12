#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"

SIGNED="$ROOT/entry/build/default/outputs/default/entry-default-signed.hap"
UNSIGNED="$ROOT/entry/build/default/outputs/default/entry-default-unsigned.hap"

echo "==> Devices:"
TARGETS="$("$HDC" list targets 2>/dev/null | tr -d '\r' || true)"
echo "$TARGETS"
if [[ -z "$TARGETS" || "$TARGETS" == "[Empty]" ]]; then
  echo "ERROR: No device. Run ./scripts/connect-device.sh first."
  exit 1
fi

HAP=""
if [[ -f "$SIGNED" ]]; then
  HAP="$SIGNED"
elif [[ -f "$UNSIGNED" ]]; then
  echo "WARN: Only unsigned HAP found. Install will likely fail until DevEco auto-sign is configured."
  HAP="$UNSIGNED"
else
  echo "ERROR: No HAP. Run ./scripts/build.sh first."
  exit 1
fi

echo "==> Installing $HAP"
"$HDC" install -r "$HAP"
echo "==> Launching com.brian.cursor.mobile"
"$HDC" shell aa start -a EntryAbility -b com.brian.cursor.mobile || true
echo "Done. Complete ACCEPTANCE_CHECKLIST.txt on device."
