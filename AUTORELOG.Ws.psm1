# AUTORELOG.Ws.psm1
# WebSocket harness cho Remote (remote.360auto.net). Chỉ capture/record + control tối thiểu.
# Đọc config từ config.json (gitignored, chứa token). KHÔNG hardcode credential.
# Giao thức được suy từ HAR (phase0.md): scr_list -> scr_list_res; act row_toggle -> act_result.
# Các trường auth/subscribe/key có thể cần chỉnh sau khi chạy Capture-Ws.ps1 và xem raw capture.

$ErrorActionPreference = 'Stop'

function Get-AutorelogConfig {
  param([string]$Path = (Join-Path $PSScriptRoot 'config.json'))
  if (-not (Test-Path $Path)) {
    throw "config.json not found at $Path. Copy config.json.sample, fill secrets (gitignored), never commit."
  }
  return Get-Content $Path -Raw | ConvertFrom-Json
}

function Send-WsText {
  param($ws, $cts, [string]$text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  $seg   = [ArraySegment[byte]]::new($bytes)
  $ws.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult() | Out-Null
}

# Ghi nhật ký WS raw ra JSONL: {ts, dir, msg}. Tự động reconnect (phục vụ B7 đo heartbeat/reconnect).
# MaxDurationSec = 0 -> chạy đến Ctrl-C.
function Start-WsCapture {
  param(
    [string]$ConfigPath  = (Join-Path $PSScriptRoot 'config.json'),
    [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
    [int]$MaxDurationSec = 0
  )
  $cfg  = Get-AutorelogConfig $ConfigPath
  $uri  = [System.Uri]::new($cfg.wsUrl)
  $writer = [System.IO.StreamWriter]::new($CapturePath, $true, [System.Text.Encoding]::UTF8)
  $cts  = [System.Threading.CancellationTokenSource]::new()
  $log  = {
    param($dir, $msg)
    $ts = (Get-Date).ToString('o')
    $line = [pscustomobject]@{ ts = $ts; dir = $dir; msg = $msg } | ConvertTo-Json -Compress
    $writer.WriteLine($line); $writer.Flush()
  }
  $backoff = 1
  $start = Get-Date
  try {
    while ($MaxDurationSec -eq 0 -or ((Get-Date) - $start).TotalSeconds -lt $MaxDurationSec) {
      $ws = $null
      try {
        $ws = [System.Net.WebSockets.ClientWebSocket]::new()
        if ($cfg.headers) { foreach ($k in $cfg.headers.PSObject.Properties.Name) { $ws.Options.SetRequestHeader($k, $cfg.headers.$k) } }
        & $log 'system' (ConvertTo-Json @{ event='connecting'; uri=$cfg.wsUrl })
        $ws.ConnectAsync($uri, $cts.Token).GetAwaiter().GetResult()
        & $log 'system' (ConvertTo-Json @{ event='open' })
        $backoff = 1
        if ($cfg.authMessage)     { Send-WsText $ws $cts $cfg.authMessage;     & $log 'send' $cfg.authMessage }
        if ($cfg.subscribeMessage) { Send-WsText $ws $cts $cfg.subscribeMessage; & $log 'send' $cfg.subscribeMessage }
        $buf = [byte[]]::new(65536)
        while ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
          $seg = [ArraySegment[byte]]::new($buf)
          $t   = $ws.ReceiveAsync($seg, $cts.Token)
          try { $t.GetAwaiter().GetResult() } catch { break }
          $res = $t.Result
          if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { break }
          $txt = [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
          & $log 'recv' $txt
        }
      } catch {
        & $log 'system' (ConvertTo-Json @{ event='error'; message = $_.Exception.Message })
      } finally {
        try { if ($ws) { $ws.Dispose() } } catch {}
      }
      if ($MaxDurationSec -ne 0 -and ((Get-Date) - $start).TotalSeconds -ge $MaxDurationSec) { break }
      & $log 'system' (ConvertTo-Json @{ event='reconnect'; waitSec = $backoff })
      Start-Sleep -Seconds $backoff
      $backoff = [math]::Min($backoff * 2, 30)
    }
  } finally {
    $writer.Dispose(); $cts.Dispose()
  }
}

# Trích instances từ 1 dòng recv scr_list_res (hỗ trợ cả rawId 0:client_xx).
function Get-ScrInstances {
  param([string]$Json)
  try {
    $o = $Json | ConvertFrom-Json
    $arr = if ($o.instances) { @($o.instances) } else { @($o) }
    $out = @()
    foreach ($i in $arr) {
      $rid = [string]$i.id
      $cid = if ($rid -match ':(.+)$') { $Matches[1] } else { $rid }
      $out += [pscustomobject]@{
        rawId   = $rid
        clientId = $cid
        idx     = $i.idx
        name    = [string]$i.name
        state   = [string]$i.state
        key     = [string]$i.key
        epoch   = $i.epoch
      }
    }
    return $out
  } catch { return @() }
}

Export-ModuleMember -Function Get-AutorelogConfig, Send-WsText, Start-WsCapture, Get-ScrInstances
