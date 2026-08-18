#!/usr/bin/env bash
# Cursor Mobile — HarmonyOS build helper
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_APP/sdk}"
export JAVA_HOME="${JAVA_HOME:-$DEVECO_APP/jbr/Contents/Home}"
export NODE_HOME="${NODE_HOME:-$DEVECO_APP/tools/node}"
OHPM_BIN="${OHPM_BIN:-$DEVECO_APP/tools/ohpm/bin}"
HVIGOR_BIN="${HVIGOR_BIN:-$DEVECO_APP/tools/hvigor/bin}"
HDC_BIN="${HDC_BIN:-$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc}"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$OHPM_BIN:$HVIGOR_BIN:$DEVECO_SDK_HOME/default/openharmony/toolchains:${PATH}"
BUILD_MODE="${BUILD_MODE:-debug}"

cd "$ROOT"
# shellcheck source=signing-overlay.sh
source "$ROOT/scripts/signing-overlay.sh"
apply_signing_overlay
trap restore_signing_overlay EXIT

echo "==> DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
echo "==> BUILD_MODE=$BUILD_MODE"
if [[ ! -f "$DEVECO_SDK_HOME/default/openharmony/ets/oh-uni-package.json" ]]; then
  echo "ERROR: HarmonyOS SDK missing under $DEVECO_SDK_HOME"
  echo "Set DEVECO_SDK_HOME / JAVA_HOME / NODE_HOME, or open DevEco Studio and install the SDK."
  exit 1
fi

echo "==> hdc targets:"
if [[ -x "$HDC_BIN" ]]; then
  "$HDC_BIN" list targets || true
else
  echo "(hdc not found)"
fi

if [[ ! -f "$ROOT/signing/debug.p7b" && ! -f "$ROOT/build-profile.local.json5" ]]; then
  echo ""
  echo "NOTE: No local signing overlay. Copy build-profile.local.json5.example"
  echo "to build-profile.local.json5 after DevEco auto-sign, or sign in the IDE."
  echo ""
fi

echo "==> ohpm install"
ohpm install

echo "==> hvigor assembleHap ($BUILD_MODE)"
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p "buildMode=$BUILD_MODE" --no-daemon

echo "==> Looking for HAP outputs..."
mkdir -p "$ROOT/dist"
find "$ROOT/entry/build" -name "*.hap" 2>/dev/null | while read -r hap; do
  echo "  $hap"
  cp -f "$hap" "$ROOT/dist/"
done
ls -lh "$ROOT/dist" || true
echo ""
echo "Next: ./scripts/install.sh"
