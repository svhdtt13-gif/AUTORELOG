param(
  [string]$ConfigPath  = (Join-Path $PSScriptRoot 'config.json'),
  [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
  [int]$MaxDurationSec = 0
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Ws.psm1') -Force

if (-not (Test-Path (Join-Path $PSScriptRoot 'config.json'))) {
  Write-Error "Thiếu config.json. Copy config.json.sample, điền token (gitignored)."
  exit 2
}

Write-Host "Recording RAW WS traffic -> $CapturePath"
Write-Host "Dùng cho B1 (stable ID) + B7 (heartbeat/reconnect). Ctrl-C để dừng."
Write-Host "Quy trình B1: để script chạy, restart Auto Ghost Story, (nếu được) restart PC, rồi Ctrl-C."
Write-Host "Sau đó chạy:  powershell -File Analyze-Capture.ps1"
Start-WsCapture -ConfigPath $ConfigPath -CapturePath $CapturePath -MaxDurationSec $MaxDurationSec
