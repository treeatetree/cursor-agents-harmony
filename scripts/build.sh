#!/usr/bin/env bash
# Cursor Mobile — HarmonyOS build helper
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
export JAVA_HOME="${JAVA_HOME:-/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home}"
export PATH="$JAVA_HOME/bin:/Applications/DevEco-Studio.app/Contents/tools/node/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains:${PATH}"
export NODE_HOME="/Applications/DevEco-Studio.app/Contents/tools/node"

cd "$ROOT"

echo "==> DEVECO_SDK_HOME=$DEVECO_SDK_HOME"
echo "==> Checking SDK components for API 24..."
if [[ ! -f "$DEVECO_SDK_HOME/default/openharmony/ets/oh-uni-package.json" ]]; then
  echo "ERROR: HarmonyOS SDK missing under $DEVECO_SDK_HOME"
  echo "Open DevEco Studio → Settings → SDK → install HarmonyOS SDK (API matching phone)."
  exit 1
fi

echo "==> hdc targets:"
HDC_BIN="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"
if [[ -x "$HDC_BIN" ]]; then
  "$HDC_BIN" list targets || true
else
  echo "(hdc not found)"
fi

if [[ ! -f "$ROOT/signing/debug.p7b" ]]; then
  echo ""
  echo "NOTE: Personal debug profile not found (signing/debug.p7b)."
  echo "In DevEco Studio:"
  echo "  1. File → Open → $ROOT"
  echo "  2. File → Project Structure → Signing Configs → Automatically generate signature"
  echo "  3. Sign in with Huawei developer account"
  echo "  4. Build → Build Hap(s)/APP(s)"
  echo ""
fi

echo "==> ohpm install (if needed)"
ohpm install || true

echo "==> hvigor assembleHap"
hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon

echo "==> Looking for HAP outputs..."
mkdir -p "$ROOT/dist"
find "$ROOT/entry/build" -name "*.hap" 2>/dev/null | while read -r hap; do
  echo "  $hap"
  cp -f "$hap" "$ROOT/dist/"
done
ls -lh "$ROOT/dist" || true
echo ""
echo "Next: configure DevEco automatic signing, then ./scripts/install.sh"
