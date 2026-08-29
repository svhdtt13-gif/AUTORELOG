param(
  [int]$Port = 8080,
  [switch]$Ngrok,
  [switch]$NoAuth
)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$web = Join-Path $ScriptDir 'Web-MasterData.ps1'

$fileArg = '"{0}"' -f $web
$arg = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $fileArg, '-Port', $Port)
if ($NoAuth) { $arg += '-NoAuth' }
Write-Host 'Starting AUTORELOG web server...'
Start-Process -FilePath powershell -ArgumentList $arg -WindowStyle Normal
Start-Sleep -Seconds 2
Write-Host ('Local:  http://localhost:' + $Port + '/')

if ($Ngrok) {
  $ngrok = Get-Command ngrok.exe -ErrorAction SilentlyContinue
  if (-not $ngrok) {
    $p = Join-Path $env:LOCALAPPDATA 'ngrok\ngrok.exe'
    if (Test-Path $p) { $ngrok = $p }
  }
  if (-not $ngrok) {
    Write-Host 'ngrok.exe not found. Install from https://ngrok.com, put ngrok.exe in PATH, then re-run with -Ngrok.'
    exit 1
  }
  $tok = $null
  $nt = Join-Path $ScriptDir 'ngrok.txt'
  if (Test-Path $nt) {
    $tok = (Get-Content $nt -Raw -Encoding UTF8 | Where-Object { $_.Trim() } | Select-Object -First 1).Trim()
  }
  $narg = @('http', [string]$Port)
  if ($tok) { $narg += @('--authtoken', $tok) }
  Write-Host 'Starting ngrok tunnel...'
  Start-Process -FilePath $ngrok.Path -ArgumentList $narg -WindowStyle Normal
  Start-Sleep -Seconds 3
  try {
    $t = Invoke-RestMethod -Uri 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 5
    $pub = ($t.tunnels | Where-Object { $_.proto -eq 'https' } | Select-Object -First 1).public_url
    if (-not $pub) { $pub = $t.tunnels[0].public_url }
    Write-Host ('Public URL (requires web token to log in): ' + $pub)
  } catch {
    Write-Host 'Could not read ngrok public URL from local API (127.0.0.1:4040). Check the ngrok window for the forwarding URL.'
  }
}
