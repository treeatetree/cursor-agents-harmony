# HM_APP — Cursor Agents on Harmony / 卓易通

Personal shell to open `https://cursor.com/agents` with an app-like experience on a Huawei phone (via 卓易通 for Android APKs).

## Layout

| Path | Role |
|------|------|
| [`android-shell/`](android-shell/) | **Current deliverable** — Android WebView shell APK (`com.brian.agents.shell`, display name Agents) |
| [`entry/`](entry/) + Harmony project files | ArkWeb attempt — **parked** (Cloudflare Turnstile); see [`PARKED.txt`](PARKED.txt) |
| [`scripts/install-android.sh`](scripts/install-android.sh) | Build signed release + push APK to device Downloads |
| [`DELIVERY.txt`](DELIVERY.txt) | Delivery notes / version changelog |

## Android shell (quick start)

```bash
export JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"

# Signing (local only — not committed): android-shell/local.properties
# RELEASE_STORE_PASSWORD=...
# RELEASE_KEY_PASSWORD=...
# RELEASE_KEY_ALIAS=cursor
# Place keystore at android-shell/keystore/cursor-release.jks (gitignored)

cd android-shell && ./gradlew assembleRelease
# or from repo root:
./scripts/install-android.sh
```

Install the APK from phone Downloads via 卓易通 (`Agents-shell.apk`).

## Compliance

Official Cursor pages only; no proxy; no password storage; no DOM injection to fake UI; reject bad SSL.
