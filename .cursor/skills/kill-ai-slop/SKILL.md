---
name: kill-ai-slop
description: >-
  Scan and strip AI-slop visual/copy tics from designs/ and UI work.
  Use when designing, restyling, or reviewing HTML mockups for this app.
---

# kill-ai-slop（本仓库）

来源：[yetone/kill-ai-slop](https://github.com/yetone/kill-ai-slop)。完整方法论在上游 `skill/SKILL.md`，不要把整库拷进本仓库。

## 每次审查

1. 读 https://raw.githubusercontent.com/yetone/kill-ai-slop/main/skill/SKILL.md
2. 对照 taxonomy：纸纹、左色条 callout、焦糖暖底、语义彩虹、毛玻璃、大阴影、发光点、emoji 装饰
3. 本项目额外约束：鸿蒙真机不用阴影当主层次；Inbox 双列；新建页画布+芯片

## 本轮已处理（designs/cursor-mobile）

- Signal：去掉纸纹点阵和 inset 铜条；底改为近中性 `#FAFAF8`；完成态用墨灰而不是绿糖
- Hero：官方蓝实色，不用 indigo→violet 渐变
- 运行中：全边框 / 字色，不用左边条 callout
