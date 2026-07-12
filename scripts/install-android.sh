#!/usr/bin/env bash
# Build signed release APK and push to Harmony device Downloads (卓易通侧安装用)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export JAVA_HOME="${JAVA_HOME:-/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"

cd "$ROOT/android-shell"
./gradlew assembleRelease
mkdir -p "$ROOT/dist"
cp -f app/build/outputs/apk/release/app-release.apk "$ROOT/dist/cursor-android-release.apk"
cp -f app/build/outputs/apk/debug/app-debug.apk "$ROOT/dist/cursor-android-debug.apk" 2>/dev/null || true

echo "APK: $ROOT/dist/cursor-android-release.apk"

DEVICE="$(hdc list targets 2>/dev/null | head -1 | awk '{print $1}')"
if [[ -n "${DEVICE:-}" && "$DEVICE" != "[Empty]" ]]; then
  DEST="/storage/media/100/local/files/Docs/Download/Agents-shell.apk"
  hdc -t "$DEVICE" file send "$ROOT/dist/cursor-android-release.apk" "$DEST"
  echo "Pushed to device: $DEST"
  echo "请在手机「文件管理 → 下载」打开 Agents-shell.apk，用卓易通安装。"
  echo "若仍提示诈骗应用：关闭 纯净模式/增强防护 后再试。"
else
  echo "无 hdc 设备；请手动拷贝 APK 到手机后经卓易通安装。"
fi
