# Cursor Agents — HarmonyOS Native

Cursor Cloud Agents 的鸿蒙原生指挥台。直连 `api.cursor.com`，不走 WebView。

## 功能

- API Key 加密存储 + `/v1/me` 校验
- Inbox（缓存优先 / 刷新 / 空态）
- 新建 Agent（仓库、分支、模型、Agent/Plan、自动 PR）
- Agent 详情：SSE 流式时间线、Outcome（PR/分支）、追问、取消
- Pura X Max：外屏 / 内屏展开 / 横竖屏断点（Stack ↔ Split）
- 网络断开横幅、轻触觉、键盘 RESIZE

## 环境

- DevEco Studio + HarmonyOS SDK（工程 target `6.1.1(24)`）
- 真机：华为 Pura X Max（亦兼容 phone/tablet）

## 构建与安装

```bash
# WiFi 调试（手机「无线调试」页的 IP:端口）
./scripts/wifi-connect.sh connect <ip:port>

# 编译
./scripts/build.sh

# 安装并启动
./scripts/install.sh
```

## 获取 API Key

打开 [cursor.com/dashboard/api](https://cursor.com/dashboard/api) 创建 User API Key（`crsr_…`），在 App 设置页粘贴验证。

## 产品边界

做：启动 / 跟进 / 追问 / 取消云端 Agent，查看结果与 PR。  
不做：IDE、Secrets/MCP 管理、Remote Desktop、网页壳。

详见验收清单 `ACCEPTANCE_CHECKLIST.txt`。
