param(
  [Parameter(Mandatory = $true)][string]$Client,
  [ValidateSet('start', 'stop', 'restart')][string]$Action = 'start',
  [int]$Minutes = 60,
  [switch]$Clear,
  [switch]$WhatIf,
  [string]$MasterPath,
  [string]$ScenePath  = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUUUU.json'
)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
Import-Module (Join-Path $ScriptDir 'AUTORELOG.Core.psm1') -Force
$OverridePath = Join-Path $ScriptDir 'overrides.json'
if (-not $MasterPath) { $MasterPath = Join-Path $ScriptDir 'clients_master.json' }

function Get-LaunchMap($scenePath) {
  $scene = Get-Content $scenePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $arr = if ($scene -is [System.Array]) { $scene } else { @($scene) }
  $map = @{}
  foreach ($e in $arr) {
    $ei = $e.emuInfo
    $cid = [string]$ei.vmName
    if (-not $cid) { if ($ei.commandLine -match '-instance:(\S+)') { $cid = $Matches[1] } }
    if ($cid) { $map[$cid] = [pscustomobject]@{ exe = $ei.executablePath; wd = $ei.workingDirectory; cmd = $ei.commandLine } }
  }
  return $map
}
function Test-InstanceRunning($cid) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    if ($cl -and (($cl -split '\s+') -contains "-instance:$cid")) { return $p.ProcessId }
  }
  return $null
}
function Start-Instance($info) {
  throw 'LOCAL_START_BLOCKED: use the remote client row to open a client'
}

$cid = $Client
$map = Get-LaunchMap $ScenePath
if (-not $map.ContainsKey($cid)) { Write-Host ("ERROR: $cid not found in scene launch map"); exit 1 }

# Clear override only
if ($Clear) {
  $ov = @{}
  if (Test-Path $OverridePath) {
    try {
      $oj = Get-Content $OverridePath -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in $oj.PSObject.Properties) { if ($k.Name -ne $cid) { $ov[$k.Name] = $k.Value } }
    } catch { }
  }
  if ($ov.Count -eq 0) { if (Test-Path $OverridePath) { Remove-Item $OverridePath -Force } }
  else { $ov | ConvertTo-Json | Set-Content $OverridePath -Encoding UTF8 }
  Write-Host ("Cleared override for $cid (returns to schedule).")
  exit 0
}

if (-not $WhatIf -and ($Action -eq 'start' -or $Action -eq 'restart')) {
  throw 'LOCAL_START_BLOCKED: use the remote client row to open a client'
}

$pidv = Test-InstanceRunning $cid
$running = ($null -ne $pidv)

if (-not $WhatIf) {
  switch ($Action) {
    'stop'    { if ($running) { Stop-Process -Id $pidv -Force; Write-Host ("STOPPED $cid (pid $pidv)") } else { Write-Host "$cid already not running" } }
    'start'   { if (-not $running) { Start-Instance $map[$cid]; Write-Host "STARTED $cid" } else { Write-Host "$cid already running" } }
    'restart' { if ($running) { Stop-Process -Id $pidv -Force; Write-Host ("STOPPED $cid (pid $pidv)") }; Start-Instance $map[$cid]; Write-Host "STARTED $cid" }
  }
} else {
  Write-Host ("[WHATIF] would $Action $cid (no process change now)")
}

# Write override so the executor loop honors it
$actionWord = if ($Action -eq 'stop') { 'stopped' } else { 'running' }
$until = (Get-Date).AddMinutes($Minutes)
$ov = @{}
if (Test-Path $OverridePath) {
  try {
    $oj = Get-Content $OverridePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in $oj.PSObject.Properties) { $ov[$k.Name] = $k.Value }
  } catch { }
}
$ov[$cid] = [ordered]@{ action = $actionWord; until = $until.ToString('yyyy-MM-dd HH:mm:ss') }
$ov | ConvertTo-Json | Set-Content $OverridePath -Encoding UTF8
Write-Host ("Override set: $cid -> $actionWord until {0:yyyy-MM-dd HH:mm:ss} (executor honors this; clears automatically after)" -f $until)
