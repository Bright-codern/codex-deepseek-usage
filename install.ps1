# 安装 Codex++ DeepSeek 消耗插件
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $MyInvocation.MyCommand.Path
$CodexPlus = Join-Path $env:APPDATA 'Codex++'
$Target = Join-Path $CodexPlus 'deepseek-usage'
$UserScripts = Join-Path $CodexPlus 'user_scripts'
$Vbs = Join-Path $Target 'start-hidden.vbs'

Write-Host '== Codex++ DeepSeek 消耗插件 安装 ==' -ForegroundColor Cyan

if (-not (Test-Path $CodexPlus)) { throw "未找到 Codex++ 目录：$CodexPlus" }

New-Item -ItemType Directory -Force -Path $UserScripts | Out-Null
New-Item -ItemType Directory -Force -Path $Target | Out-Null

Copy-Item -LiteralPath (Join-Path $Source 'deepseek-usage-panel.js') -Destination (Join-Path $UserScripts 'deepseek-usage-panel.js') -Force
Copy-Item -LiteralPath (Join-Path $Source 'helper\deepseek-usage-helper.ps1') -Destination (Join-Path $Target 'deepseek-usage-helper.ps1') -Force
Copy-Item -LiteralPath (Join-Path $Source 'helper\start-hidden.vbs') -Destination (Join-Path $Target 'start-hidden.vbs') -Force
Copy-Item -LiteralPath (Join-Path $Source 'helper\mcp-launcher.ps1') -Destination (Join-Path $Target 'mcp-launcher.ps1') -Force



$cfgPath = Join-Path $Target 'config.json'
if (-not (Test-Path $cfgPath)) {
  Copy-Item -LiteralPath (Join-Path $Source 'config.example.json') -Destination $cfgPath -Force
  Write-Host "已写入默认配置：$cfgPath"
} else {
  $migrated = $false
  try {
    $cfg = Get-Content -LiteralPath $cfgPath -Raw | ConvertFrom-Json
    if ([int]$cfg.refreshSeconds -eq 60) {
      $cfg.refreshSeconds = 360
      $cfg | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $cfgPath -Encoding UTF8
      $migrated = $true
    }
  } catch {}
  if ($migrated) { Write-Host '已将自动刷新间隔从 60 秒更新为 360 秒' }
  else { Write-Host "保留已有配置：$cfgPath" }
}

# 注册用户脚本（保留文件其余内容，只做增改）
$manifestPath = Join-Path $CodexPlus 'user_scripts.json'
$enc = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $manifestPath)) {
  [System.IO.File]::WriteAllText($manifestPath, "{`n  `"enabled`": true,`n  `"scripts`": {}`n}`n", $enc)
}
$text = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
$before = $text
foreach ($k in @('user:deepseek-usage-panel.js')) {
  if ($text -notmatch [regex]::Escape('"' + $k + '"')) {
    $text = [regex]::Replace($text, '("scripts"\s*:\s*\{)', ('$1' + "`n    `"$k`": true,"), 1)
  }
}
if ($text -ne $before) {
  Copy-Item -LiteralPath $manifestPath -Destination ($manifestPath + '.bak') -Force
  [System.IO.File]::WriteAllText($manifestPath, $text, $enc)
  Write-Host '已更新用户脚本清单（备份：user_scripts.json.bak）'
} else {
  Write-Host '用户脚本清单无需改动'
}

# 随 Codex 启动：注册为 Codex 的 MCP 服务器，由 Codex 自己拉起并在退出时回收
$startupLnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex++ DeepSeek 消耗.lnk'
if (Test-Path $startupLnk) {
  Remove-Item -LiteralPath $startupLnk -Force -ErrorAction SilentlyContinue
  Write-Host '已移除旧的开机自启快捷方式'
}

$codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
$launcher = Join-Path $Target 'mcp-launcher.ps1'
$mcpBlock = @"
[mcp_servers.deepseek_usage]
command = '$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe'
args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', '$launcher']
startup_timeout_sec = 15
"@

if (Test-Path $codexConfig) {
  $toml = [System.IO.File]::ReadAllText($codexConfig, [System.Text.Encoding]::UTF8)
  if ($toml -notmatch '\[mcp_servers\.deepseek_usage\]') {
    Copy-Item -LiteralPath $codexConfig -Destination ($codexConfig + '.dsusage.bak') -Force
    $toml = $toml.TrimEnd() + "`r`n`r`n" + $mcpBlock + "`r`n"
    [System.IO.File]::WriteAllText($codexConfig, $toml, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已注册到 Codex 配置（备份：config.toml.dsusage.bak）"
  } else {
    Write-Host 'Codex 配置中已存在该 MCP 项，跳过'
  }
} else {
  [System.IO.File]::WriteAllText($codexConfig, $mcpBlock + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
  Write-Host '已创建 Codex 配置并注册 MCP 项'
}
# 立即启动
$alreadyRunning = $false
try {
  $probe = New-Object System.Threading.Mutex($false, 'CodexPlusPlusDeepSeekUsageHelper')
  if (-not $probe.WaitOne(0)) { $alreadyRunning = $true } else { $probe.ReleaseMutex() }
  $probe.Dispose()
} catch {}
if ($alreadyRunning) {
  Write-Host '助手已在运行'
} else {
  Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $Vbs + '"') -WindowStyle Hidden
  Write-Host '助手已启动'
}

Write-Host ''
Write-Host '安装完成。回到 Codex 顶部菜单栏点击「消耗」即可查看。' -ForegroundColor Green
Write-Host '请重启一次 Codex：插件界面和后台助手都随 Codex 启动，不再随系统开机自启。'
Write-Host '（本次安装已手动拉起助手，方便马上验证数据。）'




