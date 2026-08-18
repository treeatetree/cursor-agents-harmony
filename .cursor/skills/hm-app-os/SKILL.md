---
name: hm-app-os
description: >-
  Project adapter for the HarmonyOS Cloud Agents console (cursor-agents-harmony). Use when
  changing Inbox, composer, SSE detail, settings, Tokens, or hdc install
  on this repo. Read personal dev-os first.
---

# hm-app-os

先读已安装的 `dev-os`（`~/.cursor/skills/dev-os` 或 `~/Desktop/dev-os/skills/dev-os/SKILL.md`）。

## 本仓

鸿蒙原生 **Cursor Cloud Agents 指挥台**，不是聊天 App。卓易通 WebView 壳在独立仓库 `cursor-agents-android`。

- 视觉锁：beUI。锌浅 `#FAFAFA` / 深 `#0B0B0C`。强调墨色，不要绿糖、左边条。
- 圆角：卡 16 / 芯片 12 / 输入 10。无投影。
- Inbox 封面/外屏/内屏竖 **固定双列**，卡片高 `Tokens.cardH = 116`（Split 行 68）。**禁止** `height: '100%'` 撑卡。
- 新建：空画布 + 芯片，贴顶，不是长表单。
- 过程/工具必须能点开；SSE 不得把 `collapsed` 打回 true。
- 设计大改：`designs/` HTML → 用户点头 → ArkTS。预览 `python3 -m http.server 4311 --directory designs`。
- 坑：单节点一个 `bindSheet`；`@Builder` 后不链式 `.layoutWeight`。
- 真机命令、hdc 路径：`dev-os` 的 `environment.md` + `.cursor/HANDOFF-REVIEW.md`。
- 真机走查 / Hypium：`.cursor/skills/hm-device-qa/SKILL.md`，`./scripts/device-qa.sh` + `./scripts/test.sh`（`onDeviceTest`，不要 hvigor `test`）。
- 默认不 commit。不要改 `.cursor/plans/`。

详细审查顺序和刚回滚项：`.cursor/HANDOFF-REVIEW.md`。
