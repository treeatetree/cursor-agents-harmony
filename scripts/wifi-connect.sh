#!/usr/bin/env bash
# WiFi 调试：配对 + 连接鸿蒙真机
# 用法：
#   ./scripts/wifi-connect.sh pair <ip:pairPort> <pairingCode>
#   ./scripts/wifi-connect.sh connect <ip:debugPort>
#   ./scripts/wifi-connect.sh status
set -euo pipefail

export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-/Applications/DevEco-Studio.app/Contents/sdk}"
HDC="$DEVECO_SDK_HOME/default/openharmony/toolchains/hdc"

cmd="${1:-status}"

case "$cmd" in
  pair)
    TARGET="${2:?用法: $0 pair <ip:pairPort> <pairingCode>}"
    CODE="${3:?用法: $0 pair <ip:pairPort> <pairingCode>}"
    echo "==> Pairing $TARGET ..."
    "$HDC" tconn "$TARGET" "$CODE"
    echo "==> After pair succeeds, run: $0 connect <ip:debugPort>"
    "$HDC" list targets
    ;;
  connect)
    TARGET="${2:?用法: $0 connect <ip:debugPort>}"
    echo "==> Connecting $TARGET ..."
    "$HDC" tconn "$TARGET"
    sleep 1
    "$HDC" list targets
    ;;
  status|*)
    echo "==> hdc targets:"
    "$HDC" list targets
    echo ""
    echo "Phone steps:"
    echo "  1. Same Wi-Fi as Mac"
    echo "  2. Developer options → Wireless debugging ON"
    echo "  3. Pair with pairing code → give me IP:pairPort + code"
    echo "  4. Then give IP:debugPort from Wireless debugging main page"
    ;;
esac
