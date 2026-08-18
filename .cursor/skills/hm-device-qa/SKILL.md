---
name: hm-device-qa
description: >-
  HarmonyOS Cloud Agents device QA and Hypium. Use when the user asks for 真机测试,
  走查, Hypium, hdc screenshot, Inbox/详情 visual QA, inner-screen/fold checks,
  or ./scripts/test.sh on this repo.
---

# hm-device-qa

先读 `hm-app-os`。证据进 `.cursor/review-shots/`（不提交）。Key / Bearer 不得进 hilog、截图说明、仓库。

## 两层门禁

| 层 | 命令 | 测什么 |
|----|------|--------|
| Hypium | `./scripts/test.sh` | 真机 `onDeviceTest`，装测试 HAP，约 24 例纯函数 |
| 手工走查 | `./scripts/device-qa.sh` | 页面、bindSheet、双列、Split、键盘 |

CI（ubuntu）**不跑** HAP / Hypium。`api-smoke.py` 会 POST 真 follow-up，无 Key 则 SKIP，不要扩成 E2E。

**不要**对 `entry@ohosTest` 跑 hvigor `test`：会进本地 Previewer，打印 `Darwin` 后挂死。`test.sh` 必须走 `onDeviceTest`。

走查已装包时 **不要**跑 `test.sh` / `install.sh`（会覆盖 HAP）。先记问题，再编装复验。

锁屏 `aa start` → 10106102，等用户解锁。无线端口会变；`hdc list targets` 为 `[Empty]` 时不要硬装。

## Hypium

入口：`entry/src/ohosTest/ets/test/List.test.ets`  
挂：`SseParser` / `SafeUrl` / `InboxFeed`（含图片 URL、markdown `image`、未读锚点、`phaseFromRun`、Inbox error/done、CacheLimit 新字段）。

`entry/src/test/List.test.ets` 还挂 WebAlign + ApiUnwrap（约 50+ 例）。**ohosTest ArkTS 更严**（`arkts-no-untyped-obj-literals`），不要原样 import。不要拆 `WebAlign.test.ets`。不上 UITest。

结果：`entry/.test/default/intermediates/ohosTest/coverage_data/test_result.txt`  
跑完再 `./scripts/device-qa.sh start` 把 EntryAbility 拉回来。

## 走查顺序

每步：`./scripts/device-qa.sh capture <name>`，用 `Read` 看 jpeg，`cards` 看双列。点控件：dump 里 `clickable` + bounds 中心，`./scripts/device-qa.sh click x y`。

量卡：外屏双列应等宽；高约 `Tokens.cardH=116`（dump 里 Column ≈271px @ ~2.34 px/vp）。内屏横 Split：`NavBar` 宽 ≈280vp，列表卡 `listCardH=68`（Stack ≈159px），**单列**。内屏竖：仍双列、非 Split。

1. **外屏 Inbox**：冷启动非白屏、双列齐平、头像 sheet、筛选、`+`、分组手风琴、下拉刷新。
2. **设置**：Key 仍在（不清、不重贴）、主题三段。
3. **新建**：贴顶输入；点「自动」不得关掉外层半屏（嵌套 bindSheet）。
4. **已完成详情**：标题干净、··· 出 meta、Markdown、追问栏。
5. **运行中详情**（若有）：过程默收、点开不回弹、取消/追问。
6. **系统**：切前后台；hilog 无 Key 明文（domain `0x435552`）。断网横幅需 **USB**（无线 hdc 一断就掉）。键盘顶起需用户点「追问…」。
7. **内屏**：用户展开。竖=双列；横=Split master 280 / 行 68。

问题标 P0 崩/丢数据，P1 主路径，P2 视觉。对照本地未提交改动：A 已改待装、B 仍在要修、C 仅本地新风险。

## 命令

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
./scripts/wifi-connect.sh status
./scripts/device-qa.sh start
./scripts/device-qa.sh capture qa-inbox
./scripts/device-qa.sh cards .cursor/review-shots/qa-inbox.json
./scripts/device-qa.sh click 1175 177
./scripts/test.sh
```
