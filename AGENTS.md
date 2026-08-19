# AGENTS.md

鸿蒙原生 **Cursor Cloud Agents** 指挥台（ArkTS）。产品/架构/命令详见 `README.md`、`HANDOFF.txt`、`.cursor/skills/hm-app-os/SKILL.md`、`.cursor/skills/hm-device-qa/SKILL.md`。

## Cursor Cloud specific instructions

This repo is a HarmonyOS native app. The HarmonyOS toolchain (DevEco Studio + HarmonyOS SDK) is macOS/Windows GUI tooling and is **not available on the Linux cloud VM**, so the following are **impossible here** and must run on a local Mac with DevEco + a connected Huawei device:

- `./scripts/build.sh` (HAP build via `hvigor`/`ohpm`) — hardcodes `/Applications/DevEco-Studio.app`.
- `./scripts/test.sh` (Hypium `onDeviceTest`), `./scripts/install.sh`, `./scripts/device-qa.sh` — need `hdc` + a physical device.

Do not attempt to install DevEco/HarmonyOS SDK in the cloud VM. The unit tests under `entry/src/test` and `entry/src/ohosTest` only run on-device via `onDeviceTest`; never run `hvigor ... test` on `entry@ohosTest` (it drops into the local Previewer and hangs).

### What DOES run in the cloud VM (no HarmonyOS SDK needed)

These are the same gates CI (`.github/workflows/guard.yml`) runs, plus the runnable app surfaces. All use pre-installed `python3` / `git` / `curl` — no dependency install step.

- Lint / secret gate: `bash ./scripts/check-secrets.sh` (git-grep secret scan; the primary CI gate).
- Acceptance guard: `grep -q '外屏竖屏：单栏' ACCEPTANCE_CHECKLIST.txt` must NOT match (dual-column lock).
- App core API flow: `CURSOR_API_KEY=crsr_… python3 ./scripts/api-smoke.py` — exercises the real app call chain against `https://api.cursor.com` (me → agents → runs → models → repos → createRun). **Skips (exit 0) when `CURSOR_API_KEY` is unset**; it also POSTs a real follow-up run, so only run with a key you're OK spending on. `scripts/api-smoke.sh` is the curl equivalent.
- Design prototype preview (the HTML that drives the ArkTS UI): `python3 -m http.server 4311 --directory designs`, then open `http://localhost:4311/cursor-mobile/index.html` (self-contained) or the interactive React prototype `.../cursor-mobile/App.html`. `App.html`/`Be.html`/`systems.html` etc. load React/Babel from `unpkg.com`, so they need network egress; `index.html` and `polish.html` are self-contained.

### Gotchas

- The interactive `designs/` prototypes are just HTML mockups, **not** the shipping app — they show UI/UX only, no real API calls.
- `designs/` changes are HTML-first: prototype → user sign-off → ArkTS (see `.cursor/skills/baoyu-design/SKILL.md`).
