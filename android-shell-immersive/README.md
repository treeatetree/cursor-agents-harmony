# Android shell — Cursor Agents (卓易通)

Lightweight APK that opens `https://cursor.com/agents`.

- Prefer **Chrome Custom Tabs** when a CCT-capable browser exists
- Fall back to **system WebView** (suppresses `X-Requested-With` when supported)
- Dark launch theme + desktop icon named **Cursor**

## Build

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew assembleDebug
```

APK: `app/build/outputs/apk/debug/app-debug.apk`

## Install (卓易通)

1. Copy APK to the phone / 卓易通共享目录，或用 `adb install -r app-debug.apk`（若卓易通侧 `adb` 可见）。
2. 在卓易通应用列表中打开 **Cursor**。
3. 验证：Cloudflare、登录、关闭重开后会话是否保持。

鸿蒙 ArkWeb 工程因 CF 暂搁置，见仓库根目录 `DELIVERY.txt`。
