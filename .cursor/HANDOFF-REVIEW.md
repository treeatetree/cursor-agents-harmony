# 交接：样式 / 交互审查

给下一位 agent 做 **真机视觉 + 交互细节审查**，不是功能重写。先读本文，再对照真机，再改代码。

当前分支工作已合进 main（会话体验 + 缓存/预取 + 真机 QA）。产品交接见 `HANDOFF.txt`。  
上一轮样式对话：[样式交互打磨](66638a77-6915-4ad9-8b9a-f5bdb595c93f)

---

## 产品

鸿蒙原生 **Cursor Cloud Agents 指挥台**，bundle `com.brian.cursor.mobile`。  
不是聊天 App，不是 IDE。Inbox 是任务队列，详情是对话日志 + 底栏追问。

设备：华为 Pura X Max。无线 hdc 端口会变；最近一次是 `<device-ip>:33415`。

| 屏 | 约 vp |
|---|---|
| 外屏 / 封面 | 459 × 672 |
| 内屏竖 | 664 × 939 |
| 内屏横 | 939 × 664 |

布局：封面和外屏/内屏竖 **固定双列**。只有内屏横是 Split（`useSplit = bp === 'lg' && landscape`）。Split master 宽 `Tokens.splitMasterVp` = 280，收起 rail 56。

构建 / 装机 / 截图 / 日志见文末 **环境与调试**。

**不要 commit，除非用户明确说。不要改 plan 文件。**

---

## 视觉锁定（不要回退）

- 语言：**beUI**。锌浅 `#FAFAFA` / 深 `#0B0B0C`。强调色是墨，不是蓝紫。失败用字色，完成用墨灰。**不要绿糖。**
- 圆角：卡 16 / 芯片按钮 12 / 输入 10。无投影。
- 字阶 17/16/15/14/13/12；Regular + Medium。图标 22px，热区 44（`HuIcon`）。
- kill-ai-slop：无纸纹、左边条、焦糖、彩虹状态、毛玻璃、发光点。消息 **不要左边条**。
- 封面 Inbox **固定双列、卡片等高**。新建：空画布 + 输入壳，不是长表单。
- HTML 锁定稿：`designs/cursor-mobile/Be.html`（`DESIGN.md`、`screens.jsx`、`tokens.css`）。预览：`python3 -m http.server 4311 --directory designs`，禁止 `file://`。
- 设计 skill：`.cursor/skills/baoyu-design/SKILL.md`，再读本机 `~/.agents/skills/baoyu-design/SKILL.md`。
- ArkTS：无未使用 import；`$r()` 按分支写；`@Prop` 不要叫 `size`/`color`/`fillColor`；一个节点只能一个 `bindSheet`；`@Builder` 调用上不要链式 `.layoutWeight`。

Token / 色：`entry/src/main/ets/theme/Tokens.ets`，`entry/src/main/resources/{base,dark}/element/color.json`。

---

## 当前实现落点

| 面 | 文件 |
|---|---|
| Inbox | `pages/Index.ets`，`components/InboxFilterBar.ets`，`components/AgentCard.ets` |
| 新建 | `pages/NewAgentPage.ets`，`components/PromptShell.ets` |
| 详情 / SSE | `pages/AgentDetailPage.ets`，`viewmodels/DetailVM.ets`，`components/MarkdownLite.ets`，`components/ToolCallRow.ets` |
| 设置 | `pages/SettingsPage.ets` |
| 能力 / 开关 | `components/HuButton.ets`，`HuTextButton.ets`，`HuSwitch.ets`，`HuIcon.ets` |

---

## 当前 Inbox（已合入 main / PR #9）

分组列表打平为 `header | pair | agent`，单一 `LazyForEach`（`InboxFeedSource` + `flattenCardFeed` / `flattenListFeed`）。手风琴仍一次只开一组；未标注桶保持展开。切分组 / Split 时 `rebuildFeed()`。

卡片固定高 `Tokens.cardH = 116` / `listCardH = 68`。**禁止** `height: '100%'`。标题占 2 行高，摘要占 1 行高。

审查：双列是否齐平、分组展开/收起是否刷新、单行标题是否被垂直居中得难看、摘要是否空、PR 是否误触整卡。

### 顶栏

筛选图标 + 设置图标 **收进头像**（姓名/邮箱首字）。点头像出 sheet：设置、刷新、分组、排序、按 PR、含归档。顶栏只留状态芯片、搜索（内屏）、头像、`+`。外屏不要搜索（`hideSearch` when `bp === 'sm'`）。

审查：头像是否像按钮、sheet 文案和勾选是否乱、和长按卡片菜单是否抢同一个 `bindSheet`（Index 用 `chromeKind` 共用一个 sheet）。

### 新任务输入

`PromptShell` 新建约 6 行高、**贴顶**，不再垂直居中。芯片左对齐，和追问同一套灰底 pill。图片只开系统相册。模型速度中文：快速 / 最强 / 深度 / 标准 / 思考。有变体时不立刻关 sheet。

审查：芯片是否和输入左缘齐、effort 是否还露 `effort=fast`、点图片是否只出相册。

### 设置页

改成分组卡 + **统一 48 高列表行**（左标签右值）。主题跟随/浅色/深色是轨道三段。只有粘贴 Key 才用主色 `HuButton`。不要再并排红块+灰块。

审查：行是否齐、主题三段是否错位、`@Builder themeSeg` 里 `layoutWeight` 在真机是否均分。

### 对话流

用户多次要求：

1. 顶上仓库 / 过程 / PR / 产物 **不要常驻**。收进标题箭头，点开再展开（`metaOpen`，默认关）。运行中只在标题行留短计时。
2. 已完成任务的过程折叠 **必须能点开**。根因：SSE 每次 delta / `persistTimeline` 把 `collapsed` 强制写回 `true`。现用 `pinnedOpen` + `DetailVM.toggleCollapsed` 克隆更新。
3. 展开后过程用 `MarkdownLite`。工具行没有 args 也能点开。
4. Markdown：不要左边条；引用改灰底；代码可换行；`__bold__`；段落更紧。
5. 消息全宽；用户消息只用浅底区分，不要气泡左边条。

审查：打开 **已完成** 任务，点「过程 / 推理 / 工具」能否展开并看到正文；点开后 SSE 是否又合上；标题箭头是否好找；Markdown 标题/列表/代码/链接是否可读。

---

## 用户反复说过、审查时对照

- 卡片必须 **等高**。不要为了“信息量”把高度改成 100% 或内容自适应到双列不齐。
- 对话顶栏信息块影响浏览，要收起来但找得到，不是删掉。
- 过程折叠要能点开看，不是装饰。
- 设置里按钮样式不要混（文字钮 / 色块 / 芯片混排）。
- 筛选和设置可以收进一个入口（现为头像）。
- 不要左边条。不要绿糖状态。不要图标堆砌让人看不懂。
- 外屏不要常驻搜索。新建不要长表单。

---

## 建议审查顺序（真机）

1. **外屏 Inbox**：双列卡齐平（高 116）、头像、状态芯片、`+`；分组手风琴展开后仍双列。
2. **头像 sheet**：设置 / 分组 / 排序。
3. **设置页**：列表行、主题三段、更换 Key。
4. **新任务**：贴顶输入、左对齐芯片、模型 sheet 中文速度、图片只出相册。
5. **已完成详情**：标题干净、点标题展开 meta、点过程/工具能展开、Markdown。
6. **运行中详情**（若有）：过程默认收、标题有计时、展开钉住不回弹。
7. **内屏竖**：仍双列。**内屏横**：Split master 280，列表行 68。

锁屏时 `aa start` 会失败（10106102），装完让用户解锁再开。

---

## 已知坑

- 一个节点只能一个 `bindSheet`。Index 的头像菜单和长按卡片菜单共用 `showChromeSheet` + `chromeKind`。
- `@Builder` 调用后不能链式 `.layoutWeight`。设置主题三段把 weight 写在 Builder 内部 Text 上，真机要确认有没有歪。
- `LazyForEach` 同一 key 改对象字段可能不刷新，所以折叠用克隆 `updateAt`。
- 列表 API 常常不带 `repos`，卡片仓库/摘要要等 `InboxVM.enrichRunStatuses` 之后才齐。
- 历史会话若只有 conversation API、没有 SSE cache，过程行可能只有标题没有正文——展开会空，不要再做成假折叠。
- 上一任刚把卡片搞坏又回滚。审查卡片时以 **116 固定高、双列齐** 为准，不要再拉高或改 100%。

---

## 环境与调试

### 机器

- 仓库：`.`
- 系统：macOS darwin，shell zsh
- DevEco Studio：`/Applications/DevEco-Studio.app`
- SDK：`DEVECO_SDK_HOME` 默认 `/Applications/DevEco-Studio.app/Contents/sdk`
- 工程 target：**HarmonyOS API 24**（`6.1.1(24)`）
- Java：DevEco 自带 JBR（`build.sh` 会设 `JAVA_HOME`）
- 签名：本机常没有 `signing/debug.p7b`。DevEco 打开工程 → Project Structure → Signing Configs → Automatically generate signature（华为开发者账号）。装机用 `entry/build/default/outputs/default/entry-default-signed.hap`

`hdc` **不在默认 PATH**。一律用：

```bash
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
```

或先跑 `./scripts/build.sh` / `./scripts/install.sh`（脚本会补 PATH）。

### 真机

- 机型：华为 Pura X Max（外屏 + 内屏折叠）
- bundle：`com.brian.cursor.mobile`，ability：`EntryAbility`，版本 `1.0.0` / `1000000`
- 当前无线调试：`<device-ip>:33415`（同一 Wi-Fi；端口会变）
- 锁屏时 `aa start` 失败 **10106102**（开发者模式不能自动解锁）。HAP 仍会装上，让用户解锁后再开 App

连设备：

```bash
# 看是否在线
./scripts/wifi-connect.sh status

# 已配对，只重连（无线调试主页上的 IP:调试端口，不是配对端口）
./scripts/wifi-connect.sh connect <device-ip>:33415

# 首次配对（无线调试 → 配对码）
./scripts/wifi-connect.sh pair <ip:pairPort> <pairingCode>
# 然后 connect <ip:debugPort>

# USB
./scripts/connect-device.sh
```

`hdc list targets` 为 `[Empty]` 时不要硬装。端口变了就重新 `connect`。

### 编译安装

```bash
./scripts/build.sh && ./scripts/install.sh
```

- `build.sh`：ohpm + `hvigorw assembleHap` debug，HAP 拷到 `dist/`
- `install.sh`：`hdc install -r` 已签名 HAP，再 `aa start`
- 只装不编：`./scripts/install.sh`
- API 冒烟（可选）：`CURSOR_API_KEY=… python3 ./scripts/api-smoke.py`
- 验收清单：`ACCEPTANCE_CHECKLIST.txt`（部分条目已过时，例如「外屏单栏」——产品已锁定封面双列）

手动启动：

```bash
"$HDC" shell aa start -a EntryAbility -b com.brian.cursor.mobile
```

### 截图与布局（审查必用）

PATH 里没有 `hdc` 时用上面的 `$HDC`。

```bash
# 截当前屏
"$HDC" shell snapshot_display -f /data/local/tmp/qa.jpeg
"$HDC" file recv /data/local/tmp/qa.jpeg ./.cursor/review-shots/qa.jpeg

# 控件树
"$HDC" shell uitest dumpLayout -p /data/local/tmp/layout.json
"$HDC" file recv /data/local/tmp/layout.json /tmp/hm_layout.json
```

审查截图放 `.cursor/review-shots/`（目录可自建）。用 `Read` 看 jpeg。解析 dump 时看 `text` / `description` / `bounds` / `clickable`。

走查剧本和 Hypium 边界：`.cursor/skills/hm-device-qa/SKILL.md`。截图封装：`./scripts/device-qa.sh capture <name>`。

内屏要用户把折叠屏打开；横屏要用户转过去。外屏约 1264×1848 px（vp 约 459×672）。内屏竖约 1828×2584（仍双列）；内屏横约 2584×1828（Split master 280vp，列表行 68）。

### 日志

App 用 `utils/Log.ets`，hilog domain **`0x435552`**，会打码 `crsr_…` 和 Bearer。常见 tag：`InboxVM`、`DetailVM`、`ApiKeyStore`。

```bash
# 跟日志
"$HDC" hilog | rg -i 'InboxVM|DetailVM|cursor|435552'

# 或
"$HDC" shell hilog -x | rg -i 'InboxVM|DetailVM'
```

API Key **不得**出现在 hilog 明文。不要把 Key 写进仓库、截图说明、交接文件。

### 键盘与安全区

- `EntryAbility`：`KeyboardAvoidMode.NONE`，自己跟 `TYPE_KEYBOARD` inset
- 底栏垫高：`BreakpointStore.composerBottom()` / `keyboardInsetVp`
- 页面多 `expandSafeArea TOP`，不要再叠一层假状态栏
- 外屏详情 / 新建重点测键盘是否挡住输入

### 设计预览（HTML 稿，不是真机）

```bash
python3 -m http.server 4311 --directory ./designs
```

打开 `http://localhost:4311/cursor-mobile/Be.html`。禁止 `file://`。

### 后端

- 直连 `api.cursor.com`，不走 WebView
- Key：cursor.com/dashboard/api，`crsr_…`，设置页粘贴；HUKS 加密
- 用户已有可用 Key 时不要清、不要重贴，除非他要求

### Agent 约束（再写一遍）

- 对用户用简体中文；内部思考用英文
- 不要 commit / push，除非用户明确说
- 不要改 `.cursor/plans/` 下的 plan
- 不要把 baoyu-design 上游整库拷进仓库
- 小改可直接 ArkTS；大改先 `designs/` HTML
