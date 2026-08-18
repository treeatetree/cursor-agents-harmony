# Cursor Agents — HarmonyOS Native

Cursor Cloud Agents 的鸿蒙原生指挥台。直连 `api.cursor.com`，不走 WebView。

仓库：[`treeatetree/cursor-agents-harmony`](https://github.com/treeatetree/cursor-agents-harmony)（原名 `agents-android-shell`）。  
卓易通 WebView 壳已拆到 [`treeatetree/cursor-agents-android`](https://github.com/treeatetree/cursor-agents-android)，本仓不再包含 Android 工程。

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

# 本地秘密扫描 + 编译
./scripts/check-secrets.sh
./scripts/build.sh

# 真机 Hypium（需要已连接设备）
./scripts/test.sh

# 安装并启动
./scripts/install.sh
```

GitHub Actions 只做秘密扫描和验收清单门禁；HAP / Hypium 必须在本机 DevEco 环境跑。

## 获取 API Key

打开 [cursor.com/dashboard/api](https://cursor.com/dashboard/api) 创建 User API Key（`crsr_…`），在 App 设置页粘贴验证。

## 产品边界

做：启动 / 跟进 / 追问 / 取消云端 Agent，查看结果与 PR。  
不做：IDE、Secrets/MCP 管理、Remote Desktop、网页壳。

详见验收清单 `ACCEPTANCE_CHECKLIST.txt`。
