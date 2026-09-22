# Codex++ DeepSeek 消耗：维护与交接文档

> 交接状态：当前版本 `1.0.12`（今日消费只取精确值，凭证只来自 Codex 内置浏览器）；仓库工作区干净，`main` 与 GitHub 远端同步。  
> 仓库：<https://github.com/Bright-codern/codex-deepseek-usage>  
> 平台：Windows 10 / 11。当前仅在 Codex 桌面端 + Codex++ 的组合上验证；「今日消费」的登录态只从 Codex 内置浏览器读取。

## 1. 项目目标

在 Codex 桌面端顶部原生菜单栏中加入第五个菜单项「消耗」，用于快速查看：

- DeepSeek 充值余额
- DeepSeek 今日消费
- 数据最后同步时间
- 手动刷新按钮

界面目标是尽量像 Codex 原生菜单，而不是做成独立悬浮工具。当前卡片不再显示数据来源行。

## 2. 当前功能

- 菜单顺序：`文件 | 编辑 | 视图 | 帮助 | 消耗`
- 点击「消耗」可打开或关闭卡片。
- 卡片打开后，鼠标移到「文件 / 编辑 / 视图 / 帮助」会切换到对应原生菜单。
- 原生菜单打开时，鼠标移回「消耗」会切换到卡片。
- 五个按钮之间可连续悬停切换，不需要先关闭再点击。
- 默认状态下仅悬停「消耗」不会误开卡片，仍以点击为主。
- 卡片视觉参数对齐 Codex 原生菜单：
  - 宽度 `220px`
  - 系统字体
  - 字号 `12px`
  - 行高 `18px`
  - 圆角 `7.5px`
  - 阴影 `0 4px 12px rgba(0, 0, 0, .42)`
  - 背景使用 `--color-codex-application-menu`
- 主文字使用原生 `100%` 主文字色，同步时间使用原生快捷键相同的 `75%` 辅助色。
- 自动刷新间隔默认 `360` 秒；点击「刷新」会立即触发助手重新取数。

## 3. 总体架构

```text
Codex++ / Codex 启动
        │
        ├─ Codex++ 注入 deepseek-usage-panel.js
        │      └─ 绘制「消耗」按钮和卡片
        │
        └─ Codex 启动 MCP：mcp-launcher.ps1
               └─ 启动 deepseek-usage-helper.ps1
                      ├─ 读取 DeepSeek API 数据
                      └─ 通过本机 CDP 9229 推送数据给卡片
```

核心原则：

- 页面脚本只负责 UI，不在渲染进程里直接请求 DeepSeek 接口。
- 数据采集、凭证读取和网络请求全部在外部 PowerShell 助手中完成。
- 页面和助手通过 Codex 的本机调试端口 `9229` 通信。
- MCP 只用于获得“随 Codex 启动、随 Codex 退出”的进程生命周期。

## 4. 文件职责

| 文件 | 职责 |
|---|---|
| `deepseek-usage-panel.js` | Codex 页面用户脚本：插入菜单按钮、渲染卡片、菜单悬停桥接、刷新请求。 |
| `helper/deepseek-usage-helper.ps1` | 后台数据助手：读配置、取余额、取今日消费、通过 CDP 推送数据。 |
| `helper/mcp-launcher.ps1` | MCP 启动器：Codex 启动时拉起助手，Codex 退出时回收子进程。 |
| `helper/start-hidden.vbs` | 无窗口手动启动助手的调试入口。 |
| `install.ps1` | 复制文件、注册用户脚本、写入 MCP 配置、备份配置、重启旧助手。 |
| `uninstall.ps1` | 移除 MCP 注册、用户脚本注册、助手进程和安装目录。 |
| `config.example.json` | 默认配置模板。 |
| `README.md` | 面向使用者的功能、安装、配置和排查说明。 |
| `HANDOFF.md` | 本文档，面向后续维护者。 |
| `docs/screenshot.png` | README 展示截图。 |

## 5. 安装后的实际路径

| 内容 | 路径 |
|---|---|
| 页面用户脚本 | `%APPDATA%\Codex++\user_scripts\deepseek-usage-panel.js` |
| 助手目录 | `%APPDATA%\Codex++\deepseek-usage` |
| 助手脚本 | `%APPDATA%\Codex++\deepseek-usage\deepseek-usage-helper.ps1` |
| MCP 启动器 | `%APPDATA%\Codex++\deepseek-usage\mcp-launcher.ps1` |
| 配置 | `%APPDATA%\Codex++\deepseek-usage\config.json` |
| 最近一次数据 | `%APPDATA%\Codex++\deepseek-usage\last-payload.json` |
| 助手日志 | `%APPDATA%\Codex++\deepseek-usage\helper.log` |
| 启动器日志 | `%APPDATA%\Codex++\deepseek-usage\launcher.log` |
| Codex 配置 | `%USERPROFILE%\.codex\config.toml` |
| Codex++ 脚本清单 | `%APPDATA%\Codex++\user_scripts.json` |

本地配置、日志、备份和运行状态均已列入 `.gitignore`，不要提交。

## 6. 运行流程

1. Codex++ 启动 Codex，并注入 `deepseek-usage-panel.js`。
2. Codex 根据 `~/.codex/config.toml` 启动 `mcp-launcher.ps1`。
3. MCP 启动器拉起 `deepseek-usage-helper.ps1`。
4. 助手读取 `config.json`，并解析页面脚本中的 `@version`。
5. 助手通过 CDP 轮询主窗口：
   - 如果页面没有当前版本 UI，则注入 `deepseek-usage-panel.js`。
   - 读取并清除 `window.__dsUsageRefreshFlag`。
6. 首次启动、到达刷新周期或用户点击「刷新」时，助手执行取数（「今日消费」的 `userToken` 从 Codex 内置浏览器存储里读取）。
7. 助手通过 `window.__dsUsageApply(payload)` 把数据推送给页面。
8. 卡片只在打开状态渲染数据；关闭后数据仍保存在 `window.__DSUsage`。
9. Codex 退出后，MCP 启动器结束助手进程。

## 7. 关键接口与 DOM 契约

### 页面全局对象

| 名称 | 用途 |
|---|---|
| `window.__dsUsageUIVersion` | 当前已注入的 UI 版本，防止同版本重复初始化。 |
| `window.__dsUsageApply(payload)` | 助手向页面推送最新数据。 |
| `window.__dsUsageRefreshFlag` | 卡片请求立即刷新。助手读取后重置为 `false`。 |
| `window.__DSUsage` | 页面中的最近一次数据。 |
| `window.__dsUsageMenuGuard` | 菜单级联事件监听器，避免脚本升级后重复注册。 |

### DOM ID

| 名称 | 用途 |
|---|---|
| `ds-usage-menu-trigger` | 自定义「消耗」按钮。 |
| `ds-usage-panel` | 自定义卡片。 |
| `application-menu-trigger-file-menu` | 原生「文件」按钮。 |
| `application-menu-trigger-edit-menu` | 原生「编辑」按钮。 |
| `application-menu-trigger-view-menu` | 原生「视图」按钮。 |
| `application-menu-trigger-help-menu` | 原生「帮助」按钮。 |
| `application-menu-content` | 原生菜单弹出层。 |

### 原生菜单桥接

Codex 当前的原生菜单由 React/Radix 管理。为了从卡片首次切入原生菜单，页面脚本会读取按钮上的 `__reactProps$...` 并调用其 `onPointerDown`。这是当前实现中最依赖 Codex 内部结构的部分。

如果 Codex 升级后出现“卡片正常，但移到原生菜单不打开”，优先检查：

- 原生按钮 ID 是否仍存在。
- 按钮是否仍有 `__reactProps$...`。
- `onPointerDown` 是否仍用于打开菜单。
- 菜单是否仍位于 `[role=menubar]` 下。

## 8. 数据获取与口径

### 充值余额

- API：`https://api.deepseek.com/user/balance`
- 凭证：优先使用 `config.json` 中的 `apiKey`；未配置时读取 `~/.codex/auth.json` 的 `OPENAI_API_KEY`。
- 展示字段：`topped_up_balance`
- 未展示 `total_balance` 和 `granted_balance`，仅保留在内部 payload 中。

### 今日消费

优先使用 DeepSeek 网页版接口：

- API：`https://platform.deepseek.com/api/v0/usage/by_api_key/cost`
- 凭证：只从 **Codex 内置浏览器** 的 Local Storage LevelDB 里读 `userToken`，取最后一个匹配值，路径为
  `%APPDATA%\Codex\web\Codex\<profile>\Partitions\<partition>\Local Storage\leveldb`（同时兼容 `%LOCALAPPDATA%\Packages\OpenAI.Codex_*\LocalCache\Roaming\...` 形式）。
- 不读取 Chrome / Chrome Beta / Edge，也不再支持 `config.json` 的 `platformToken`：Chrome 136+ 禁止对默认配置目录开启调试端口，Cookie 又是 app-bound 加密，外部拿不到可用登录态；内置浏览器就在 Codex 进程里，登录态持久且读取最直接。
- 统计方式：当天各模型、各小时 `cost` 求和。
- 时间范围基于系统本地时区计算。README 中的“北京时间”表述只适用于系统时区为中国时区的用户。

取不到凭证或接口失败时：

- **不做估算**。助手把 `todaySpend` 置为 `null`，并在 `todaySpendUnavailable` 里写明原因（`请先在 Codex 内置浏览器登录 DeepSeek` / `登录态过期，请在 Codex 内置浏览器重新登录`）。
- 界面在数字位置显示 `—`，并在下方显示该原因；`todaySpendSource` 只在取到精确值时为 `platform`。
- 因此卡片上的「今日消费」要么是精确值，要么是 `—`，不会出现估算值。

### Payload 主要字段

```json
{
  "ok": true,
  "currency": "CNY",
  "symbol": "¥",
  "totalBalance": 0.0,
  "toppedUpBalance": 0.0,
  "grantedBalance": 0.0,
  "todaySpend": 0.0,
  "todaySpendSource": "platform",
  "todaySpendUnavailable": null,
  "updatedAt": 0,
  "error": null
}
```

## 9. 安装、升级与卸载

### 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

安装脚本会：

- 复制页面脚本和助手文件到 `%APPDATA%\Codex++`。
- 将用户脚本注册到 `user_scripts.json`。
- 将 MCP 启动器写入 `~/.codex/config.toml`。
- 保留已有 `config.json`。
- 结束旧助手并启动新版助手。
- 提示首次使用需在 Codex 内置浏览器登录 DeepSeek 网页版（否则「今日消费」显示 `—`）。
- 对修改过的配置做 `.bak` 备份。

### 升级

1. 修改 `deepseek-usage-panel.js` 顶部 `@version` 和内部 `VERSION`，两者必须一致。
2. 执行 `node --check .\deepseek-usage-panel.js`。
3. 执行 `ParseFile` 检查 PowerShell 语法，或直接运行 `install.ps1` 验证。
4. 执行 `install.ps1`。
5. 重启 Codex，让所有渲染窗口重新加载用户脚本。
6. 验证卡片内容、菜单悬停、刷新和日志。

缺少第 1 步会导致助手持续认为页面版本过期并反复注入旧脚本，严重时可能让页面卡死。安装脚本已经会在升级时重启助手，但页面脚本版本号仍需手工维护。

### 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

卸载后重启 Codex，菜单栏中的「消耗」按钮会消失。

## 10. 开发与调试

推荐顺序：

```powershell
node --check .\deepseek-usage-panel.js

$files = @('.\install.ps1', '.\helper\deepseek-usage-helper.ps1', '.\helper\mcp-launcher.ps1')
foreach ($f in $files) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $f), [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { $errors | ForEach-Object { "$f`: $($_.Message)" } }
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

调试数据采集：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File "$env:APPDATA\Codex++\deepseek-usage\deepseek-usage-helper.ps1" -Once
```

调试菜单和卡片：

- 查看主窗口调试目标：`http://127.0.0.1:9229/json/list`
- 确认页面版本：`window.__dsUsageUIVersion`
- 确认卡片状态：是否存在 `#ds-usage-panel`
- 确认数据推送：`window.__DSUsage`
- 只在主窗口测试，包含 `avatar-overlay` 的目标不是菜单栏所在页面。

注意：直接热注入不同版本页面脚本时，旧版 `MutationObserver` 和新版可能互相覆盖。正式升级应使用 `install.ps1` 并重启 Codex，不要在旧页面里同时保留两个版本。

## 11. 回归验证清单

每次发布前至少检查：

- 点击「消耗」能打开和关闭卡片。
- 默认关闭状态只悬停「消耗」不会误开。
- 「消耗 → 文件 → 帮助 → 消耗 → 编辑 → 视图」连续悬停切换正常。
- 卡片宽度、字体、颜色、圆角和阴影与原生菜单一致。
- 标题「DeepSeek 消耗」为 `600` 字重。
- 主文字为 `100%` 原生文字色，同步时间为 `75%` 辅助色。
- 卡片只显示余额、今日消费、同步时间和刷新，不显示来源行。
- 点击「刷新」后助手日志出现 `refresh requested from panel`。
- 余额与网页版数据口径一致。
- 网页版登录态失效时，「今日消费」显示 `—` 并提示重新登录（不再估算）。
- 暗色主题和亮色主题均可正常显示。
- `install.ps1` 和 `uninstall.ps1` 可重复执行。

## 12. 已知风险与技术债

- 原生菜单桥接依赖 React 内部属性 `__reactProps$...` 和 Radix 行为，Codex 升级后可能失效。
- 原生按钮 ID、`[role=menubar]` 和菜单 DOM 结构属于内部实现，不是公开稳定 API。
- 今日消费使用 DeepSeek 网页版内部接口，DeepSeek 改版后可能失效。
- 从 Codex 内置浏览器 LevelDB 读取 `userToken` 依赖当前的存储格式与 `userToken` 键名，Codex 或 DeepSeek 改版后可能失效；失效时卡片会显示 `—` 并提示重新登录。
- 登录态只认 Codex 内置浏览器：用户在 Chrome / Edge 里的 DeepSeek 登录态不会生效。
- 因为不做估算，未登录或登录态失效时「今日消费」没有数字可看；这是有意的取舍。
- `mcp-launcher.ps1` 中的 MCP `serverInfo.version` 仍是 `1.1.0`，与 UI `1.0.11` 独立；如需统一版本体系，应另行整理。
- `mcp-launcher.ps1` 仍有未使用的 `BridgePath` 和注释遗留，不影响当前运行，但可以清理。
- 当前只验证 Windows，未处理 macOS 路径、凭证存储和进程生命周期差异。

## 13. 版本与提交记录

| 版本 / 提交 | 内容 |
|---|---|
| 原版 `v1.0.3` | 基础菜单按钮、卡片、余额与消费采集。 |
| `696007b` | 增加菜单悬停切换、原生视觉统一、助手升级重启。 |
| `e24a66b` | README 补充相对原版的更新说明。 |
| `daff01e` | 修正卡片文字颜色，主色 `100%`、辅助色 `75%`。 |
| `e0f9f29` | 移除来源说明行，更新截图，发布 `1.0.10`。 |
| `v1.0.12` | 「今日消费」凭证只从 Codex 内置浏览器读取：移除 Chrome / Edge 扫描、`platformToken` 配置项和余额差值估算；安装时提示登录。 |

## 14. 后续维护建议

1. 优先保持“UI 只画界面、助手负责取数”的边界，不要把网络请求搬进页面脚本。
2. 升级任何页面脚本时，同时更新 `@version` 和 `VERSION`。
3. 每次修改卡片样式后，对照原生菜单的实际计算样式，而不是只看截图猜颜色。
4. Codex 升级后先验证菜单桥接，再验证取数。
5. 每次发布同步更新 `README.md`、`HANDOFF.md` 和 `docs/screenshot.png`。
