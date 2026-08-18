#!/usr/bin/env bash
# Run Hypium ohosTest on a connected HarmonyOS device.
# GitHub Actions cannot compile HAP / run these tests (no HarmonyOS SDK).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVECO_APP="${DEVECO_APP:-/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_APP/sdk}"
export JAVA_HOME="${JAVA_HOME:-$DEVECO_APP/jbr/Contents/Home}"
export NODE_HOME="${NODE_HOME:-$DEVECO_APP/tools/node}"
OHPM_BIN="${OHPM_BIN:-$DEVECO_APP/tools/ohpm/bin}"
HVIGOR_BIN="${HVIGOR_BIN:-$DEVECO_APP/tools/hvigor/bin}"
export PATH="$JAVA_HOME/bin:$NODE_HOME/bin:$OHPM_BIN:$HVIGOR_BIN:$DEVECO_SDK_HOME/default/openharmony/toolchains:${PATH}"

cd "$ROOT"
# shellcheck source=signing-overlay.sh
source "$ROOT/scripts/signing-overlay.sh"
apply_signing_overlay
trap restore_signing_overlay EXIT

echo "==> hvigor entry@ohosTest"
hvigorw --mode module -p module=entry@ohosTest -p product=default test --no-daemon
