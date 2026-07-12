# Android shell — Agents（卓易通）

全屏 WebView 打开 `https://cursor.com/agents`（无浏览器地址栏）。

- 官方 Cursor App Icon + 桌面名 **Agents**
- v1.2：`startUpWebView` 异步预热、DNS/prefetch、BFCache、prerender（能力随系统 WebView 降级）
- Cookie / 缓存持久化；热启动不重载
- 文件选择、下载、麦克风；错误页可「系统浏览器」应急

## Build

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew assembleRelease
```

或仓库根目录：`scripts/install-android.sh`

APK：`app/build/outputs/apk/release/app-release.apk` → `../dist/cursor-android-release.apk`
