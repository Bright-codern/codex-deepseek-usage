# 卸载 Codex++ DeepSeek 消耗插件
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall.ps1

$ErrorActionPreference = 'Stop'
$CodexPlus = Join-Path $env:APPDATA 'Codex++'
$Target = Join-Path $CodexPlus 'deepseek-usage'
$TaskName = 'CodexPlusPlus-DeepSeekUsage'

Write-Host '== Codex++ DeepSeek 消耗插件 卸载 ==' -ForegroundColor Cyan

try {
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  & schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
  $ErrorActionPreference = $previous
} catch {
  $ErrorActionPreference = 'Stop'
}
$lnkPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex++ DeepSeek 消耗.lnk'
Remove-Item -LiteralPath $lnkPath -Force -ErrorAction SilentlyContinue

# 从 Codex 配置里摘掉 MCP 注册（这是"随 Codex 启动"的那一环）
$codexConfig = Join-Path $env:USERPROFILE '.codex\config.toml'
if (Test-Path $codexConfig) {
  $toml = [System.IO.File]::ReadAllText($codexConfig, [System.Text.Encoding]::UTF8)
  if ($toml -match '\[mcp_servers\.deepseek_usage') {
    Copy-Item -LiteralPath $codexConfig -Destination ($codexConfig + '.dsusage.bak') -Force
    $kept = New-Object System.Collections.Generic.List[string]
    $skipping = $false
    foreach ($line in [System.IO.File]::ReadAllLines($codexConfig)) {
      if ($line -match '^\s*\[') { $skipping = ($line -match '^\s*\[mcp_servers\.deepseek_usage(\]|\.)') }
      if (-not $skipping) { $kept.Add($line) }
    }
    while ($kept.Count -gt 0 -and $kept[$kept.Count - 1].Trim() -eq '') { $kept.RemoveAt($kept.Count - 1) }
    [System.IO.File]::WriteAllText($codexConfig, (($kept -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '已从 Codex 配置移除 MCP 注册（备份：config.toml.dsusage.bak）'
  }
}

# 停掉两个后台助手。排除本进程：命令行里也带着这些关键字的话会把自己杀掉。
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -like '*deepseek-usage-helper.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Write-Host '已停止助手进程、移除自启项与 MCP 注册'

$manifestPath = Join-Path $CodexPlus 'user_scripts.json'
if (Test-Path $manifestPath) {
  $enc = New-Object System.Text.UTF8Encoding($false)
  $text = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
foreach ($key in @('user:deepseek-usage-panel.js')) {
    $text = [regex]::Replace($text, '\s*"' + [regex]::Escape($key) + '"\s*:\s*true,?', '')
  }
  $text = $text -replace ',(\s*\}\s*$)', '$1'
  [System.IO.File]::WriteAllText($manifestPath, $text, $enc)
}
Remove-Item -LiteralPath (Join-Path $CodexPlus 'user_scripts\deepseek-usage-panel.js') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $Target -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '已移除插件文件。重启 Codex 后菜单栏的「消耗」按钮会消失。' -ForegroundColor Green


