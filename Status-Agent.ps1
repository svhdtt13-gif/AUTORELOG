param(
  [string]$MasterPath,
  [string]$ScenePath = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUU.json'
)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
if (-not $MasterPath) { $MasterPath = Join-Path $ScriptDir 'clients_master.json' }
Import-Module (Join-Path $ScriptDir 'AUTORELOG.Core.psm1') -Force

function Test-InstanceRunning($cid) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    if ($cl -and (($cl -split '\s+') -contains "-instance:$cid")) { return $true }
  }
  return $false
}
function Get-Overrides() {
  $o = @{}
  $p = Join-Path $ScriptDir 'overrides.json'
  if (Test-Path $p) {
    try {
      $j = Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($k in $j.PSObject.Properties) {
        $ov = $k.Value; $u = $null
        if ($ov.until -and [datetime]::TryParse([string]$ov.until, [ref]$u)) { $o[$k.Name] = @{ action = [string]$ov.action; until = $u } }
      }
    } catch { }
  }
  return $o
}

$master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
$windows = Get-ScheduleWindows $master
$now = Get-NowInTz
$overrides = Get-Overrides

Write-Host ("AUTORELOG status @ {0:HH:mm} (Asia/Ho_Chi_Minh)" -f $now)
Write-Host 'Schedule windows:'
foreach ($w in $windows) { Write-Host ('  {0,-5} {1} -> {2}' -f $w.group, $w.open, $w.close) }
if ($overrides.Count -gt 0) { Write-Host ('Active overrides: {0}' -f ($overrides.Keys -join ', ')) }

$total = 0; $running = 0; $drift = 0
Write-Host ''
Write-Host ('{0,-10} {1,-16} {2,-6} {3,-8} {4,-8} {5,-10} {6}' -f 'CLIENT', 'NAME', 'GRP', 'DESIRED', 'RUNNING', 'OVERRIDE', 'DRIFT')
foreach ($c in @($master.clients)) {
  $cid = [string]$c.client
  $desired = Get-DesiredState $c $windows $now
  $ovStr = '-'
  if ($overrides.ContainsKey($cid) -and $now -lt $overrides[$cid].until) { $desired = $overrides[$cid].action; $ovStr = $overrides[$cid].action }
  $isRun = Test-InstanceRunning $cid
  $total++
  if ($isRun) { $running++ }
  if ($desired -eq 'running' -and -not $isRun) { $dr = 'YES(up)' }
  elseif (($desired -eq 'stopped' -or $desired -eq 'blocked') -and $isRun) { $dr = 'YES(down)' }
  else { $dr = '-' }
  if ($dr -ne '-') { $drift++ }
  Write-Host ('{0,-10} {1,-16} {2,-6} {3,-8} {4,-8} {5,-10} {6}' -f $cid, [string]$c.name, [string]$c.group, $desired, $(if ($isRun) { 'yes' } else { 'no' }), $ovStr, $dr)
}
Write-Host ''
Write-Host ('Total={0}  running={1}  drift={2}' -f $total, $running, $drift)
if ($drift -gt 0) { Write-Host 'DRIFT detected -> executor auto-corrects within 1 min (or run Executor-Agent.ps1 -Apply).' }
else { Write-Host 'No drift: actual state matches schedule (incl. overrides).' }
