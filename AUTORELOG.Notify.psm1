$ErrorActionPreference = 'Stop'

function Send-Notify {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'notify.json')
  )
  # 1) Windows toast (always, via helper)
  try {
    Start-Process -WindowStyle Hidden powershell -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Show-Alert.ps1'),'-Message',$Message)
  } catch { }

  # 2) Load config (secrets live in notify.json, gitignored)
  $cfg = $null
  if (Test-Path $ConfigPath) {
    try { $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $cfg = $null }
  }
  if (-not $cfg) { return }

  # 3) Telegram
  if ($cfg.telegram -and [string]$cfg.telegram.token -and [string]$cfg.telegram.chatId) {
    try {
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
      $uri = "https://api.telegram.org/bot$($cfg.telegram.token)/sendMessage"
      $body = @{ chat_id = [string]$cfg.telegram.chatId; text = $Message } | ConvertTo-Json -Compress
      $r = Invoke-RestMethod -Uri $uri -Method Post -ContentType 'application/json; charset=utf-8' -Body $body -TimeoutSec 10
      if (-not $r.ok) {
        Add-Content -Path (Join-Path $PSScriptRoot 'alerts.log') -Encoding UTF8 -Value (('{0:yyyy-MM-dd HH:mm:ss} ALERT telegram-fail {1}:{2}' -f (Get-Date), $r.error_code, $r.description))
      }
    } catch {
      try { Add-Content -Path (Join-Path $PSScriptRoot 'alerts.log') -Encoding UTF8 -Value (('{0:yyyy-MM-dd HH:mm:ss} ALERT telegram-fail {1}' -f (Get-Date), $_)) } catch { }
    }
  }

  # Future channels (discord / email / webhook) can be added here, driven by $cfg.
}

Export-ModuleMember -Function Send-Notify
