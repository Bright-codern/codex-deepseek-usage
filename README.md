# Codex++ DeepSeek 消耗

给 Codex 桌面端顶部菜单栏加一个「消耗」按钮，随时看 DeepSeek 的**充值余额**和**今日消费**。

```
文件 | 编辑 | 视图 | 帮助 | 消耗
```

![效果](docs/screenshot.png)

点开就是这样一张小卡片：只有两行数字、同步时间和刷新按钮。不点刷新的话每 360 秒自动同步一次。

> 官网那个「账户总额」= 充值余额 + 赠送额度。只充过值的时候两者是同一个数，摆两遍没有意义，所以没有列出来。

---

## 本次更新（v1.0.12）

相对 `v1.0.10`，改动集中在「今日消费」的取数口径和凭证来源：

- **凭证来源收敛**：只从 **Codex 内置浏览器** 读取「今日消费」的登录态，不再扫描 Chrome / Edge。内置浏览器就跑在 Codex 进程里，登录态持久、读取最直接。

- **不再估算**：删除「余额差值」回退，「今日消费」只显示网页版接口查到的精确值。
- **不可用时明说**：取不到网页版登录态时，数字位置显示 `—`，下方提示「请先在 Codex 内置浏览器登录 DeepSeek」，不再用估算值冒充精确值。
- **清理死代码**：移除余额差值状态文件 `state.json` 及其相关逻辑。

此前版本（v1.0.4–v1.0.10）主要完善菜单交互和卡片视觉：

- **菜单联动**：点击「消耗」展开卡片后，鼠标移到「文件 / 编辑 / 视图 / 帮助」会直接打开对应原生菜单；从原生菜单移回「消耗」也会自动切回卡片。
- **连续悬停切换**：五个菜单按钮之间可以平滑移动切换，不再需要每次先关闭再重新点击。
- **状态同步**：同步按钮的 `aria-expanded` 与 `data-state`，卡片打开和关闭状态与原生菜单保持一致。
- **原生视觉统一**：卡片宽度、字体、字号、文字位置、背景、圆角和阴影均对齐 Codex 原生菜单；标题「DeepSeek 消耗」加粗。
- **文字颜色统一**：菜单主文字使用原生 `100%` 主色，同步时间使用与原生快捷键相同的 `75%` 辅助色。
- **刷新按钮样式**：改为原生菜单式悬停高亮，不再使用独立的描边按钮样式。
- **卡片精简**：移除「来源：…」说明行，只保留余额、消费、同步时间和刷新按钮。
- **升级稳定性**：助手会根据界面脚本中的 `@version` 判断版本；安装新版时自动结束旧助手并启动新版，避免旧脚本反复覆盖新版页面。
- **文档与截图**：补充新版交互说明，并更新 README 展示截图。

## 特性

- **只看两个数**：充值余额、今日消费，没有别的。
- **像原生菜单一样切换**：点击「消耗」展开，可在「文件 / 编辑 / 视图 / 帮助 / 消耗」之间悬停切换；卡片沿用 Codex 菜单的字体、底色、圆角和阴影。
- **不需要单独配置密钥**：余额用 `~/.codex/auth.json` 里现有的 key；今日消费的登录态直接从 **Codex 内置浏览器** 的本地存储里读，需要保持内置浏览器里的网页版登录。
- **随 Codex 启动、随 Codex 退出**，不随系统开机自启，不常驻托盘。
- **装在用户目录**，不碰 Codex 安装目录，卸载能还原。

## 工作原理

Codex 主进程不允许渲染进程自己发 HTTP 请求，所以整个东西分成两半：

```
┌─ Codex 窗口（渲染进程）─────────────────────┐
│  deepseek-usage-panel.js                    │
│  往菜单栏插「消耗」按钮 + 渲染小卡片          │
└───────────────▲─────────────────────────────┘
                │ 调试端口（CDP，只连本机回环）
┌───────────────┴─────────────────────────────┐
│  deepseek-usage-helper.ps1                  │
│  取余额 / 取今日消费 → 推给卡片               │
└─────────────────────────────────────────────┘
                ▲
                │ 由 Codex 作为 MCP 服务器拉起
        mcp-launcher.ps1
```

页面脚本只负责画界面，**一个字节的数据都不由它去取**；取数全部在外部助手进程里完成，通过调试端口把结果推回页面。

### 数据来源

| 指标 | 来源 | 说明 |
|---|---|---|
| 充值余额 | `https://api.deepseek.com/user/balance` | 官方接口，用 `~/.codex/auth.json` 里的 `OPENAI_API_KEY`，取 `topped_up_balance` |
| 今日消费 | `https://platform.deepseek.com/api/v0/usage/by_api_key/cost` | 就是网页版 `platform.deepseek.com/usage` 选「今日」看到的数字，按模型逐小时 cost 求和 |

「今日消费」的凭证由助手自动从 **Codex 内置浏览器** 的 `Local Storage\leveldb` 里读 `userToken`：

**在 Codex 里打开 `platform.deepseek.com` 扫码登录一次，之后就不用管了。** 内置浏览器的配置目录是持久的，登录状态能长期保留。

> 为什么不直接用你日常的 Chrome：Chrome 136 之后不再允许对默认配置目录开调试端口，登录凭证又是 app-bound 加密的，插件从外部读不到可用登录态；而内置浏览器就在 Codex 进程里，读起来最直接。所以插件只认内置浏览器。

取不到登录态时**不做任何估算**：卡片在数字位置显示 `—`，并在下方写明原因（未登录 / 登录态失效）。
这样卡片上的数字只有一种含义——网页版查到的精确值。

### 为什么用 MCP 挂启动

Codex 桌面端没有别的「随应用启动」扩展点：启动文件夹是随系统开机，不符合要求；而 MCP 服务器正好是
Codex 启动时拉起、退出时回收的。

所以安装脚本在 `~/.codex/config.toml` 里写一小段 `[mcp_servers.deepseek_usage]` 指向 `mcp-launcher.ps1`。
这个启动器只干一件事：**Codex 起来 → 拉起助手；Codex 退出 → 关掉助手**。
顺带它还暴露一个 `deepseek_usage` 工具，让 Codex 自己也能读到那份数据。

## 环境要求

- Windows 10 / 11
- [Codex 桌面端](https://openai.com/codex)（本插件依赖它的调试端口和用户脚本机制）
- [Codex++](https://github.com/BigPizzaV3/CodexPlusPlus)（把用户脚本注入 Codex 的启动器）
- 在 **Codex 内置浏览器** 里登录过 DeepSeek 网页版（只为「今日消费」这一项；安装时会提示你去登录）

## 安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1
```

装完在 Codex 内置浏览器里打开 <https://platform.deepseek.com> 登录一次，「今日消费」才有数字（没登录时显示 `—`）。

然后**重启一次 Codex**，点顶部菜单栏的「消耗」。

脚本会备份改过的文件（`config.toml.dsusage.bak`、`user_scripts.json.bak`），重复运行不会重复写入。

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1
```

会停掉助手、移除启动文件夹里的旧快捷方式、从 `config.toml` 摘掉 MCP 注册，并删除插件文件。
重启 Codex 后「消耗」按钮消失。

## 配置

`%APPDATA%\Codex++\deepseek-usage\config.json`

| 字段 | 默认 | 说明 |
|---|---|---|
| `debugPort` | `9229` | Codex++ 启动 Codex 时带的调试端口 |
| `refreshSeconds` | `360` | 自动刷新间隔（秒） |
| `pollSeconds` | `2` | 助手轮询页面的间隔（秒） |
| `apiKey` | 空 | 留空则读 `~/.codex/auth.json` 的 `OPENAI_API_KEY` |
| `uiScript` | 空 | 一般不用填 |

## 排查

日志：

- 助手：`%APPDATA%\Codex++\deepseek-usage\helper.log`
- 启动器：`%APPDATA%\Codex++\deepseek-usage\launcher.log`

常见情况：

| 现象 | 原因 / 处理 |
|---|---|
| 卡片显示「等待助手进程…」 | 助手没在跑。看 `launcher.log` 有没有 `spawned`；也可以双击 `%APPDATA%\Codex++\deepseek-usage\start-hidden.vbs` 手动拉起 |
| 「获取失败：未找到 DeepSeek API Key」 | `~/.codex/auth.json` 里没有 `OPENAI_API_KEY`，或在 `config.json` 里填 `apiKey` |
| 「今日消费」显示 `—` 并提示登录 | Codex 内置浏览器里没有 DeepSeek 网页版的登录态。打开 `platform.deepseek.com` 扫码登录一次即可（插件不从 Chrome / Edge 读取） |
| 重启 Codex 后助手没被带起来 | 多半是 Codex 重写 `~/.codex/config.toml` 时把 `[mcp_servers.deepseek_usage]` 抹掉了，重跑一次 `install.ps1` 补写 |

## 已知限制

- 「今日消费」走的是网页版内部接口（不是公开 API），**DeepSeek 改版时可能失效**；因为不做估算，失效时卡片会直接显示 `—` 并提示，而不是给一个错数。
- 助手每 2 秒连一次本地调试端口，属于轻量轮询。
- 「今日」按北京时间算，跨时区使用需要自行调整。
- 「今日消费」的登录态只从 Codex 内置浏览器读取，你在 Chrome / Edge 里的登录态不会被使用。
- 只在 Windows 上验证过。

## 目录结构

```
deepseek-usage-panel.js        注入 Codex 页面的用户脚本（菜单栏按钮 + 卡片）
HANDOFF.md                     维护与交接文档
config.example.json            默认配置
install.ps1 / uninstall.ps1    安装 / 卸载
helper/
  deepseek-usage-helper.ps1    取数并推给页面
  mcp-launcher.ps1             随 Codex 启动，拉起 / 回收助手
  start-hidden.vbs             无窗口启动助手（调试用）
docs/
  screenshot.png
```

## 维护与交接

架构、约定、调试流程、升级步骤和已知风险见 [HANDOFF.md](HANDOFF.md)。

## 许可

[MIT](LICENSE)

## 免责声明

非官方项目，与 OpenAI、DeepSeek 均无关联。使用「今日消费」所依赖的网页版内部接口可能违反其服务条款，
请自行判断。本项目只读取你自己的账户数据，不发送到任何第三方。
