---
name: baoyu-design
description: >-
  Systematic UI design for this HarmonyOS Cloud Agents client using the
  baoyu-design methodology. Use when the user asks to design, restyle, mock up,
  prototype, visually QA, polish screens, optimize chips/layout/tokens, or
  continue 设计优化. HTML mockups live under designs/; production UI is ArkTS.
---

# baoyu-design（本仓库）

来源：[JimLiu/baoyu-design](https://github.com/JimLiu/baoyu-design)。完整方法论在本机 skill，不要把整个上游仓库拷进本 App 仓库。

## 每次设计任务必须先做

1. 立刻阅读并遵循：`~/.agents/skills/baoyu-design/SKILL.md`
2. 再读同目录 `system-prompt.md` 与 `references/cursor.md`
3. 按任务加载 built-in skill。本项目默认是 **Mobile app design**：
   - `built-in-skills/mobile-prototype.md`
   - `built-in-skills/hi-fi-design.md`
   - `built-in-skills/interactive-prototype.md`
4. 若是从现有界面抽设计系统：`built-in-skills/design-system-authoring-guide.md`
5. 若项目已绑定系统：先读 `designs/<project>/_d_meta.json`，再读每个 `_ds/<slug>/_ds_prompt.md`

## 本仓库约束（覆盖 HTML 默认假设）

- **交付分两层**：先在 `designs/<project>/` 出可预览 HTML（封面约 459×672、内屏竖约 664×939）；用户认可后再改 ArkTS，不要只改 HTML 就当上线。
- **实现落点**：`entry/src/main/ets/theme/Tokens.ets`、`entry/src/main/resources/{base,dark}/element/color.json`、`pages/`、`components/`。
- **现有视觉语言（未另指定前保持）**：Quiet cards；无投影；圆角 card 16 / chip 12 / field 10；accent 少用；封面 Inbox **固定双列**；新建页空画布 + 底栏芯片，不堆表单。
- **设备**：华为 Pura X Max，外屏 + 内屏。不要画假状态栏。
- **预览**：`python3 -m http.server 4311 --directory designs`，用浏览器打开 `http://localhost:4311/...`，禁止 `file://`。
- 设计产物只放 `designs/`，不要散落到仓库根目录。

## 已有参考

- 真机/模拟器截图：`.cursor/review-shots/`
- 产品骨架：`.cursor/plans/cloud_agents_原生设计_fef50a12.plan.md`
