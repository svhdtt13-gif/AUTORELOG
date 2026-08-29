param(
  [string]$MasterPath = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$ScenePath  = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUUUU.json',
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Core.psm1') -Force

$master = Get-Content $MasterPath -Raw -Encoding UTF8 | ConvertFrom-Json
$scene  = Get-Content $ScenePath -Raw -Encoding UTF8 | ConvertFrom-Json
$arr    = if ($scene -is [System.Array]) { $scene } else { @($scene) }

# Map client_XX -> launch info from scene
$launch = @{}
foreach ($e in $arr) {
  $ei = $e.emuInfo
  $cid = [string]$ei.vmName
  if (-not $cid) { if ($ei.commandLine -match '-instance:(\S+)') { $cid = $Matches[1] } }
  if ($cid) {
    $launch[$cid] = [pscustomobject]@{
      exe = $ei.executablePath
      wd  = $ei.workingDirectory
      cmd = $ei.commandLine
    }
  }
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
  $cmd = $info.cmd
  $args = $cmd
  if ($args -match '^"([^"]+)"\s*(.*)$') { $args = $Matches[2] }
  else { $args = $args.Substring($info.exe.Length).Trim() }
  Start-Process -FilePath $info.exe -ArgumentList $args -WorkingDirectory $info.wd -WindowStyle Minimized
}

function Stop-Instance($runPid) {
  Stop-Process -Id $runPid -Force
}

$windows = Get-ScheduleWindows $master
$now = Get-NowInTz
Write-Host ("Now (Asia/Ho_Chi_Minh): {0:HH:mm}  Apply={1}" -f $now, $Apply)

$actions = @()
foreach ($c in @($master.clients)) {
  $cid = [string]$c.client
  $desired = Get-DesiredState $c $windows $now
  $runningPid = Test-InstanceRunning $cid
  $running = ($null -ne $runningPid)
  $act = 'NONE'
  switch ($desired) {
    'running' { if (-not $running) { $act = 'START' } }
    'stopped' { if ($running) { $act = 'STOP' } }
    'blocked' { if ($running) { $act = 'STOP' } }
    default   { $act = 'NONE' }
  }
  if ($act -eq 'START' -and -not $launch.ContainsKey($cid)) {
    Write-Host ("  [WARN] $cid desired=running but no launch cmd in scene -> SKIP")
    $act = 'SKIP'
  }
  $actions += [pscustomobject]@{ client = $cid; name = [string]$c.name; desired = $desired; running = $running; action = $act }
  Write-Host ('  {0,-10} {1,-12} desired={2,-8} running={3,-5} -> {4}' -f $cid, $c.name, $desired, $running, $act)
  if ($Apply) {
    if ($act -eq 'START') { try { Start-Instance $launch[$cid]; Write-Host "    STARTED $cid" } catch { Write-Host "    START FAIL $cid : $_" } }
    elseif ($act -eq 'STOP') { try { Stop-Instance $runningPid; Write-Host "    STOPPED $cid (pid $runningPid)" } catch { Write-Host "    STOP FAIL $cid : $_" } }
  }
}

if (-not $Apply) { Write-Host "`nDRY-RUN: nothing changed. Re-run with -Apply to actually start/stop instances." }
