param(
  [switch]$Once
)

$ErrorActionPreference = 'Stop'

if (-not $Once) {
  $script:InstanceMutex = New-Object System.Threading.Mutex($false, 'CodexPlusPlusDeepSeekUsageHelper')
  if (-not $script:InstanceMutex.WaitOne(0)) { exit 0 }
}

$Root = Join-Path $env:APPDATA 'Codex++\deepseek-usage'
$ConfigPath = Join-Path $Root 'config.json'
$StatePath = Join-Path $Root 'state.json'
$LastPayloadPath = Join-Path $Root 'last-payload.json'
$LogPath = Join-Path $Root 'helper.log'

New-Item -ItemType Directory -Force -Path $Root | Out-Null

function Write-Log([string]$Message) {
  $line = '[{0}] {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Message
  try {
    if ((Test-Path $LogPath) -and ((Get-Item $LogPath).Length -gt 262144)) {
      Remove-Item $LogPath -Force -ErrorAction SilentlyContinue
    }
    Add-Content -Path $LogPath -Value $line -Encoding UTF8
  } catch {}
}

function Get-Config {
  $defaults = [ordered]@{
    debugPort = 9229
    refreshSeconds = 360
    pollSeconds = 2
    apiKey = ''
    platformToken = ''
    uiScript = ''
  }
  $cfg = $null
  if (Test-Path $ConfigPath) {
    try { $cfg = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json } catch { Write-Log "config parse failed: $($_.Exception.Message)" }
  }
  $out = @{}
  foreach ($k in $defaults.Keys) {
    $v = $null
    if ($cfg -and ($cfg.PSObject.Properties.Name -contains $k)) { $v = $cfg.$k }
    if ($null -eq $v -or ($v -is [string] -and $v.Trim() -eq '')) { $v = $defaults[$k] }
    $out[$k] = $v
  }
  return $out
}

function Get-ApiKey($cfg) {
  if ($cfg.apiKey) { return [string]$cfg.apiKey }
  $authPath = Join-Path $env:USERPROFILE '.codex\auth.json'
  if (Test-Path $authPath) {
    try {
      $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json
      if ($auth.OPENAI_API_KEY) { return [string]$auth.OPENAI_API_KEY }
    } catch { Write-Log "auth.json parse failed: $($_.Exception.Message)" }
  }
  return ''
}

function Get-Balance($apiKey) {
  $headers = @{ Authorization = "Bearer $apiKey"; Accept = 'application/json' }
  $resp = Invoke-RestMethod -Uri 'https://api.deepseek.com/user/balance' -Headers $headers -Method Get -TimeoutSec 20
  if (-not $resp.balance_infos -or $resp.balance_infos.Count -eq 0) { throw 'balance_infos empty' }
  $info = $resp.balance_infos[0]
  return [ordered]@{
    currency = $info.currency
    total = [double]$info.total_balance
    granted = [double]$info.granted_balance
    toppedUp = [double]$info.topped_up_balance
  }
}

function Get-PlatformTokenFromChrome {
  $found = $null
  $roots = @(
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome Beta\User Data'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data')
  )
  foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    $profiles = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile*' }
    foreach ($profile in $profiles) {
      $ls = Join-Path $profile.FullName 'Local Storage\leveldb'
      if (-not (Test-Path $ls)) { continue }
      $files = Get-ChildItem -LiteralPath $ls -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in '.log', '.ldb' } | Sort-Object LastWriteTime
      foreach ($f in $files) {
        $bytes = $null
        try {
          $fs = New-Object System.IO.FileStream($f.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
          $ms = New-Object System.IO.MemoryStream
          $fs.CopyTo($ms)
          $fs.Close()
          $bytes = $ms.ToArray()
          $ms.Close()
        } catch { continue }
        if (-not $bytes -or $bytes.Length -eq 0) { continue }
        foreach ($text in @([System.Text.Encoding]::UTF8.GetString($bytes), [System.Text.Encoding]::Unicode.GetString($bytes))) {
          foreach ($m in [regex]::Matches($text, 'userToken[^{]{0,10}\{"value":"((?:[^"\\]|\\.)*)"')) {
            $candidate = $m.Groups[1].Value
            if ($candidate.Length -ge 20) { $found = $candidate }
          }
        }
      }
    }
  }
  return $found
}

function Get-PlatformTodaySpend($token) {
  if (-not $token) { return $null }
  $now = Get-Date
  $startSec = [long][DateTimeOffset]::new($now.Date).ToUnixTimeSeconds()
  $endSec = [long][DateTimeOffset]::new($now.Date.AddDays(1)).ToUnixTimeSeconds()
  $rawOffset = [int]([TimeZoneInfo]::Local.GetUtcOffset($now).TotalSeconds)
  $tzSec = 3600 * [Math]::Floor($rawOffset / 3600)
  $shift = $rawOffset - $tzSec
  $uri = "https://platform.deepseek.com/api/v0/usage/by_api_key/cost?start=$($startSec + $shift)&end=$($endSec + $shift)&tz=$tzSec"
  $headers = @{
    Authorization = "Bearer $token"
    Accept = 'application/json'
    Referer = 'https://platform.deepseek.com/usage'
    Origin = 'https://platform.deepseek.com'
    'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36'
  }
  $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec 25
  if ($resp.data -and $resp.data.biz_code -and [int]$resp.data.biz_code -ne 0) { throw "platform biz error $($resp.data.biz_code): $($resp.data.biz_msg)" }
  if ($resp.code -and [int]$resp.code -ne 0) { throw "platform error $($resp.code): $($resp.msg)" }
  $biz = $resp.data.biz_data
  if (-not $biz) { throw 'platform response missing biz_data' }
  $sum = 0.0
  $currency = $null
  foreach ($entry in @($biz.data)) {
    if (-not $entry) { continue }
    if (-not $currency -and $entry.currency) { $currency = $entry.currency }
    foreach ($series in @($entry.series)) {
      if (-not $series) { continue }
      foreach ($bucket in @($series.buckets)) {
        if (-not $bucket) { continue }
        $cost = $bucket.cost
        if ($null -ne $cost -and "$cost" -ne '') { $sum += [double]$cost }
      }
    }
  }
  return [ordered]@{ cost = $sum; currency = $currency }
}

function Get-State {
  if (Test-Path $StatePath) {
    try { return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) } catch {}
  }
  return $null
}

function Save-State($state) {
  try { $state | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatePath -Encoding UTF8 } catch {}
}

function Update-BalanceDelta($state, [double]$balance, [string]$today) {
  $nowSec = [long][DateTimeOffset]::new((Get-Date)).ToUnixTimeSeconds()
  $reliable = $false
  if (-not $state -or -not $state.day) {
    $state = [ordered]@{ day = $today; dayStartBalance = $balance; dayStartReliable = $false; lastBalance = $balance; lastSampleAt = $nowSec; topUp = 0.0 }
    $reliable = $false
  } elseif ($state.day -ne $today) {
    $gap = $nowSec - [long]$state.lastSampleAt
    $reliable = ($gap -le 900)
    $state = [ordered]@{ day = $today; dayStartBalance = [double]$state.lastBalance; dayStartReliable = $reliable; lastBalance = $balance; lastSampleAt = $nowSec; topUp = 0.0 }
  } else {
    $prev = [double]$state.lastBalance
    if ($balance -gt $prev + 1e-9) { $state.topUp = [double]$state.topUp + ($balance - $prev) }
    $state.lastBalance = $balance
    $state.lastSampleAt = $nowSec
    $reliable = [bool]$state.dayStartReliable
  }
  $spend = [double]$state.dayStartBalance + [double]$state.topUp - $balance
  if ($spend -lt 0) { $spend = 0.0 }
  Save-State $state
  return [ordered]@{ cost = $spend; reliable = $reliable }
}

# ---------- CDP (short-lived connections: the app drops idle sessions) ----------

function Invoke-PageExpression([string]$Expression, [int]$Port, [int]$TimeoutSec = 12) {
  $result = $null
  $ws = $null
  try {
    $list = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 5
    $pages = @($list | Where-Object { $_.type -eq 'page' -and $_.url -like 'app://*' })
    # 应用里有多个渲染进程（主窗口、头像浮层…），菜单栏只在主窗口里。
    # 之前直接取第一个，命中的是头像浮层，数据推过去主窗口收不到，卡片一直显示"等待助手进程"。
    $target = $pages | Where-Object { $_.url -notlike '*avatar-overlay*' } | Select-Object -First 1
    if (-not $target) { $target = $pages | Select-Object -First 1 }
    if (-not $target) { return $null }

    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ct = [System.Threading.CancellationToken]::None
    $connect = $ws.ConnectAsync([Uri]$target.webSocketDebuggerUrl, $ct)
    if (-not $connect.Wait(5000)) { return $null }

    $payload = @{ id = 1; method = 'Runtime.evaluate'; params = @{ expression = $Expression; returnByValue = $true; awaitPromise = $true; userGesture = $true } } | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
    $send = $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$bytes)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct)
    if (-not $send.Wait(5000)) { return $null }

    $buf = New-Object byte[] 1048576
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
      $seg = New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)
      $task = $ws.ReceiveAsync($seg, $ct)
      if (-not $task.Wait(3000)) { continue }
      $res = $task.Result
      if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
      if ($res.Count -le 0) { continue }
      $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
      if (-not $text.StartsWith('{"id"')) { continue }
      $message = $null
      try { $message = $text | ConvertFrom-Json } catch { continue }
      if ($message.id -ne 1) { continue }
      if ($message.result -and $message.result.result -and ($message.result.result.PSObject.Properties.Name -contains 'value')) {
        $result = $message.result.result.value
      }
      break
    }
  } catch {
    $result = $null
  } finally {
    if ($ws) { try { $ws.Dispose() } catch {} }
  }
  return $result
}

# ---------- collect ----------

$cfg = Get-Config
$apiKey = Get-ApiKey $cfg
$uiPath = $cfg.uiScript
if (-not $uiPath) { $uiPath = Join-Path $env:APPDATA 'Codex++\user_scripts\deepseek-usage-panel.js' }
$script:ChromeToken = $null

$uiSource = ''
if (Test-Path $uiPath) {
  $uiSource = Get-Content -LiteralPath $uiPath -Raw
} else {
  Write-Log "ui script not found: $uiPath"
}

$uiScriptVersion = '1.0.3'
if ($uiSource -match '(?m)^//\s*@version\s+([^\s]+)') {
  $uiScriptVersion = [string]$Matches[1]
}

$probeExpression = @"
(function(){
  if (window.__dsUsageUIVersion !== '$uiScriptVersion') {
$uiSource
  }
  var refresh = window.__dsUsageRefreshFlag === true;
  window.__dsUsageRefreshFlag = false;
  return JSON.stringify({ ui: !!window.__dsUsageUIVersion, refresh: refresh });
})()
"@

function Collect {
  $payload = [ordered]@{
    ok = $false
    currency = 'CNY'
    symbol = '¥'
    totalBalance = $null
    toppedUpBalance = $null
    grantedBalance = $null
    todaySpend = $null
    todaySpendSource = $null
    todaySpendLowerBound = $false
    updatedAt = [long][DateTimeOffset]::new((Get-Date)).ToUnixTimeMilliseconds()
    error = $null
  }
  try {
    if (-not $apiKey) { throw '未找到 DeepSeek API Key' }
    $balance = Get-Balance $apiKey
    $payload.ok = $true
    $payload.currency = $balance.currency
    if ($balance.currency -eq 'USD') { $payload.symbol = '$' } else { $payload.symbol = '¥' }
    $payload.totalBalance = [Math]::Round($balance.total, 2)
    $payload.toppedUpBalance = [Math]::Round($balance.toppedUp, 2)
    $payload.grantedBalance = [Math]::Round($balance.granted, 2)

    $today = (Get-Date).ToString('yyyy-MM-dd')
    $platform = $null
    $token = [string]$cfg.platformToken
    if (-not $token) {
      if (-not $script:ChromeToken) {
        $script:ChromeToken = Get-PlatformTokenFromChrome
        if ($script:ChromeToken) { Write-Log 'platform token read from browser profile' }
      }
      if ($script:ChromeToken) { $token = [string]$script:ChromeToken }
    }
    if ($token) {
      try { $platform = Get-PlatformTodaySpend $token }
      catch {
        Write-Log "platform usage failed: $($_.Exception.Message)"
        if (-not $cfg.platformToken) {
          $script:ChromeToken = $null
          $fresh = Get-PlatformTokenFromChrome
          if ($fresh -and $fresh -ne $token) {
            $script:ChromeToken = $fresh
            try { $platform = Get-PlatformTodaySpend $fresh } catch { Write-Log "platform retry failed: $($_.Exception.Message)" }
          }
        }
      }
    }
    if ($platform) {
      $payload.todaySpend = [Math]::Round([double]$platform.cost, 2)
      $payload.todaySpendSource = 'platform'
      if ($platform.currency) {
        $payload.currency = $platform.currency
        if ($platform.currency -eq 'USD') { $payload.symbol = '$' } else { $payload.symbol = '¥' }
      }
    } else {
      $delta = Update-BalanceDelta (Get-State) $balance.total $today
      $payload.todaySpend = [Math]::Round([double]$delta.cost, 2)
      $payload.todaySpendSource = 'balance'
      if (-not [bool]$delta.reliable) { $payload.todaySpendLowerBound = $true }
    }
  } catch {
    $payload.ok = $false
    $payload.error = $_.Exception.Message
    Write-Log "collect failed: $($_.Exception.Message)"
  }
  return $payload
}

function Publish($payload) {
  $json = $payload | ConvertTo-Json -Depth 6 -Compress
  try { Set-Content -LiteralPath $LastPayloadPath -Value $json -Encoding UTF8 } catch {}
  Invoke-PageExpression "window.__dsUsageApply && window.__dsUsageApply($json)" ([int]$cfg.debugPort) | Out-Null
}

if ($Once) {
  $payload = Collect
  $payload | ConvertTo-Json -Depth 6
  Publish $payload
  exit 0
}

Write-Log 'helper started'
$lastFetch = [datetime]::MinValue
$pending = $true
$lastProbe = [datetime]::MinValue
$connectedOnce = $false

while ($true) {
  $now = Get-Date
  if (($now - $lastProbe).TotalSeconds -ge [int]$cfg.pollSeconds) {
    $lastProbe = $now
    $raw = Invoke-PageExpression $probeExpression ([int]$cfg.debugPort) 8
    if ($raw -is [string] -and $raw.StartsWith('{')) {
      if (-not $connectedOnce) { Write-Log 'codex window found'; $connectedOnce = $true }
      try {
        $probe = $raw | ConvertFrom-Json
        if ($probe.refresh) { $pending = $true; Write-Log 'refresh requested from panel' }
      } catch {}
    } elseif ($connectedOnce) {
      Write-Log 'codex window not reachable'
      $connectedOnce = $false
    }
  }

  $due = ((Get-Date) - $lastFetch).TotalSeconds -ge [int]$cfg.refreshSeconds
  if ($pending -or $due) {
    $pending = $false
    $lastFetch = Get-Date
    $payload = Collect
    Publish $payload
  }

  Start-Sleep -Milliseconds 400
}


