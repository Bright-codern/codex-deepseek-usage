# Codex 启动时由 Codex 自己拉起本进程；本进程再拉起两个后台助手，并在 Codex 退出后把它们一起收掉。
# 之所以做成 MCP 服务器：这是 Codex 唯一"随应用启动、随应用退出"的扩展点，不需要开机自启。
#
#   1. deepseek-usage-helper.ps1  采集 DeepSeek 余额与今日消费

param(
  [string]$HelperPath = '',
  [string]$BridgePath = ''
)

$ErrorActionPreference = 'Continue'

$Root = Join-Path $env:APPDATA 'Codex++\deepseek-usage'
$BridgeRoot = Join-Path $env:APPDATA 'Codex++\translate-bridge'
$LauncherLog = Join-Path $Root 'launcher.log'

function Write-LauncherLog([string]$Message) {
  try {
    Add-Content -Path $LauncherLog -Value ('[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message) -Encoding UTF8
  } catch {}
}

if (-not $HelperPath) { $HelperPath = Join-Path $Root 'deepseek-usage-helper.ps1' }
if (-not $BridgePath) { $BridgePath = Join-Path $BridgeRoot 'translate-bridge.ps1' }

# stdout 只允许输出 JSON-RPC，日志一律走文件
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

$children = @()
foreach ($child in @(
  @{ Name = 'usage-helper'; Path = $HelperPath }
)) {
  try {
    if (Test-Path $child.Path) {
      $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $child.Path) -WindowStyle Hidden -PassThru
      $children += $proc
      Write-LauncherLog "$($child.Name) spawned (pid $($proc.Id))"
    } else {
      Write-LauncherLog "$($child.Name) not found: $($child.Path)"
    }
  } catch {
    Write-LauncherLog "$($child.Name) spawn failed: $($_.Exception.Message)"
  }
}

function Send-Response($Id, $Result) {
  $payload = @{ jsonrpc = '2.0'; id = $Id; result = $Result } | ConvertTo-Json -Depth 10 -Compress
  [Console]::Out.WriteLine($payload)
  [Console]::Out.Flush()
}

function Send-Error($Id, [int]$Code, [string]$Message) {
  $payload = @{ jsonrpc = '2.0'; id = $Id; error = @{ code = $Code; message = $Message } } | ConvertTo-Json -Depth 10 -Compress
  [Console]::Out.WriteLine($payload)
  [Console]::Out.Flush()
}

try {
  while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }

    $line = $line.Trim()
    if ($line -eq '') { continue }

    $message = $null
    try { $message = $line | ConvertFrom-Json } catch { continue }

    $id = $message.id
    if ($null -eq $id) { continue }

    switch ($message.method) {
      'initialize' {
        $protocol = $message.params.protocolVersion
        if (-not $protocol) { $protocol = '2025-06-18' }
        Send-Response $id @{
          protocolVersion = $protocol
          capabilities = @{ tools = @{} }
          serverInfo = @{ name = 'deepseek-usage'; version = '1.1.0' }
        }
      }
      'tools/list' {
        Send-Response $id @{ tools = @(
          @{
            name = 'deepseek_usage'
            description = '读取 DeepSeek 充值余额与今日消费。数据由本地助手进程采集，刷新间隔见 config.json。'
            inputSchema = @{ type = 'object'; properties = @{}; additionalProperties = $false }
          }
        ) }
      }
      'tools/call' {
        if ($message.params.name -ne 'deepseek_usage') {
          Send-Error $id -32602 "unknown tool: $($message.params.name)"
        } else {
          $payloadPath = Join-Path $Root 'last-payload.json'
          $body = '助手尚未取到数据，请在 Codex 顶部菜单栏点开「消耗」后重试。'
          if (Test-Path $payloadPath) {
            try { $body = [System.IO.File]::ReadAllText($payloadPath, [System.Text.Encoding]::UTF8) } catch {}
          }
          Send-Response $id @{ content = @(@{ type = 'text'; text = $body }); isError = $false }
        }
      }
      'resources/list' { Send-Response $id @{ resources = @() } }
      'prompts/list' { Send-Response $id @{ prompts = @() } }
      'ping' { Send-Response $id @{} }
      default { Send-Error $id -32601 "method not found: $($message.method)" }
    }
  }
} catch {
  Write-LauncherLog "stdio loop failed: $($_.Exception.Message)"
}

foreach ($proc in $children) {
  try {
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force }
  } catch {}
}
Write-LauncherLog 'helpers stopped (codex exited)'
Write-LauncherLog 'launcher exiting'
