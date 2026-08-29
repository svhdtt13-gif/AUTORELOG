param(
  [string]$ConfigPath  = (Join-Path $PSScriptRoot 'config.json'),
  [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
  [int]$MaxDurationSec = 0
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Ws.psm1') -Force

if (-not (Test-Path (Join-Path $PSScriptRoot 'config.json'))) {
  Write-Error "Missing config.json. Copy config.json.sample and fill token (gitignored)."
  exit 2
}

Write-Host "Recording RAW WS traffic -> $CapturePath"
Write-Host "For B1 (stable id) + B7 (heartbeat/reconnect). Ctrl-C to stop."
Write-Host "B1: keep running, restart Auto Ghost Story (and PC), then Ctrl-C."
Write-Host "Then run:  powershell -File Analyze-Capture.ps1"
Start-WsCapture -ConfigPath $ConfigPath -CapturePath $CapturePath -MaxDurationSec $MaxDurationSec
