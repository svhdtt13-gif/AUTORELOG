param(
  [string]$MasterPath = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$ScenePath  = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUUUU.json'
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Core.psm1') -Force

function Test-InstanceRunning($cid) {
  $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    $cl = $p.CommandLine
    if ($cl -and (($cl -split '\s+') -contains "-instance:$cid")) { return $true }
  }
  return $false
}

$master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
$windows = Get-ScheduleWindows $master
$now = Get-NowInTz

Write-Host ("AUTORELOG status @ {0:HH:mm} (Asia/Ho_Chi_Minh)" -f $now)
Write-Host 'Schedule windows:'
foreach ($w in $windows) { Write-Host ('  {0,-5} {1} -> {2}' -f $w.group, $w.open, $w.close) }

$total = 0; $running = 0; $drift = 0
Write-Host ''
Write-Host ('{0,-10} {1,-16} {2,-6} {3,-8} {4,-8} {5}' -f 'CLIENT', 'NAME', 'GRP', 'DESIRED', 'RUNNING', 'DRIFT')
foreach ($c in @($master.clients)) {
  $cid = [string]$c.client
  $desired = Get-DesiredState $c $windows $now
  $isRun = Test-InstanceRunning $cid
  $total++
  if ($isRun) { $running++ }
  if ($desired -eq 'running' -and -not $isRun) { $dr = 'YES(up)' }
  elseif (($desired -eq 'stopped' -or $desired -eq 'blocked') -and $isRun) { $dr = 'YES(down)' }
  else { $dr = '-' }
  if ($dr -ne '-') { $drift++ }
  Write-Host ('{0,-10} {1,-16} {2,-6} {3,-8} {4,-8} {5}' -f $cid, [string]$c.name, [string]$c.group, $desired, $(if ($isRun) { 'yes' } else { 'no' }), $dr)
}
Write-Host ''
Write-Host ('Total={0}  running={1}  drift={2}' -f $total, $running, $drift)
if ($drift -gt 0) { Write-Host 'DRIFT detected -> executor auto-corrects within 1 min (or run Executor-Agent.ps1 -Apply).' }
else { Write-Host 'No drift: actual state matches schedule.' }
