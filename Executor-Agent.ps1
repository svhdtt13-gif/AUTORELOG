param(
  [string]$MasterPath = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$ScenePath  = 'C:\Users\ADMIN\Desktop\MIUUUUUUUUUU.json',
  [switch]$Apply
)
$ErrorActionPreference = 'Stop'
$LogPath   = Join-Path $PSScriptRoot 'executor.log'
$AlertPath = Join-Path $PSScriptRoot 'alerts.log'
$StatePath = Join-Path $PSScriptRoot 'lastrun.json'

function Log($m){ Add-Content -Path $LogPath -Encoding UTF8 -Value (('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $m)) }
function Alert($m){
  $line = ('{0:yyyy-MM-dd HH:mm:ss} ALERT {1}' -f (Get-Date), $m)
  Add-Content -Path $AlertPath -Encoding UTF8 -Value $line
  Write-Host ('  [ALERT] ' + $m)
  try { Send-Notify -Message $m } catch { Add-Content -Path $AlertPath -Encoding UTF8 -Value (('{0:yyyy-MM-dd HH:mm:ss} ALERT notify-fail {1}' -f (Get-Date), $_)) }
}
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Notify.psm1') -Force

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

# Previous run state (for crash detection)
$prev = @{}
if (Test-Path $StatePath) {
  try {
    $s = Get-Content $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($s.running) { foreach ($k in $s.running.PSObject.Properties) { $prev[$k.Name] = $k.Value } }
  } catch { $prev = @{} }
}

$windows = Get-ScheduleWindows $master
$now = Get-NowInTz

# Manual overrides (temporary schedule override, written by Control-Client.ps1)
$overrides = @{}
$OverridePath = Join-Path $PSScriptRoot 'overrides.json'
if (Test-Path $OverridePath) {
  try {
    $oj = Get-Content $OverridePath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in $oj.PSObject.Properties) {
      $ov = $k.Value
      $until = $null
      if ($ov.until -and [datetime]::TryParse([string]$ov.until, [ref]$until)) { $overrides[$k.Name] = @{ action = [string]$ov.action; until = $until } }
    }
  } catch { $overrides = @{} }
}

# Zombie recovery: process sống nhưng chưa kết nối game
$zr = @{}
$zrPath = Join-Path $PSScriptRoot 'zombie_restart.json'
if (Test-Path $zrPath) {
  try {
    $zj = Get-Content $zrPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($k in $zj.PSObject.Properties) {
      $v = $k.Value
      $zr[$k.Name] = [ordered]@{ last = [datetime]::Parse([string]$v.last); attempts = [int]$v.attempts; broken = [bool]$v.broken }
    }
  } catch { $zr = @{} }
}
$zombieCooldownMin = 15
$zombieMaxAttempts = 3
$graceSec = 120

Write-Host ("Now (Asia/Ho_Chi_Minh): {0:HH:mm}  Apply={1}" -f $now, $Apply)
Log ("RUN Apply=$Apply Now={0:HH:mm} TZ=Asia/Ho_Chi_Minh" -f $now)
$cStart = 0; $cStop = 0; $cNone = 0; $cSkip = 0; $cCrash = 0; $cFail = 0; $cZombie = 0
$newRunning = @{}

$actions = @()
foreach ($c in @($master.clients)) {
  $cid = [string]$c.client
  $desired = Get-DesiredState $c $windows $now
  if ($overrides.ContainsKey($cid) -and $now -lt $overrides[$cid].until) { $desired = $overrides[$cid].action }
  $runningPid = Test-InstanceRunning $cid
  $running = ($null -ne $runningPid)
  $connected = if ($running) { Test-InstanceConnected $cid } else { $false }
  if ($connected -and $zr.ContainsKey($cid)) { $zr.Remove($cid) }
  $act = 'NONE'; $event = 'OK'
   switch ($desired) {
     'running' {
       if (-not $running) { $act = 'START' }
       elseif (-not $connected) {
         $pObj = Get-InstanceProcess $cid
         $age = 99999
         if ($pObj -and $pObj.CreationDate) {
           try { $born = [System.Management.ManagementDateTimeConverter]::ToDateTime($pObj.CreationDate); $age = (Get-Date).Subtract($born).TotalSeconds } catch { }
         }
         if ($age -ge $graceSec) { $act = 'ZOMBIE_RESTART' }
       }
     }
     'stopped' { if ($running) { $act = 'STOP' } }
     'blocked' { if ($running) { $act = 'STOP' } }
     default   { $act = 'NONE' }
   }
   if ($act -eq 'ZOMBIE_RESTART') { $event = 'ZOMBIE' }
  if ($act -eq 'START') {
    if (-not $launch.ContainsKey($cid)) {
      Write-Host ("  [WARN] $cid desired=running but no launch cmd in scene -> SKIP")
      Log ("WARN $cid desired=running but no launch cmd in scene -> SKIP")
      $act = 'SKIP'
    } elseif ($prev.ContainsKey($cid) -and $prev[$cid] -eq $true) {
      $event = 'CRASH'   # was running last cycle, now gone -> unexpected off
    } else {
      $event = 'SCHED_START'
    }
  } elseif ($act -eq 'STOP') {
    $event = if ($desired -eq 'blocked') { 'ORPHAN_STOP' } else { 'SCHED_STOP' }
  }

  if ($act -eq 'START' -and -not $launch.ContainsKey($cid)) { $cSkip++ }
   else {
     switch ($act) { 'START' { $cStart++ } 'STOP' { $cStop++ } 'NONE' { $cNone++ } 'ZOMBIE_RESTART' { $cZombie++ } }
   }

  if ($Apply) {
    if ($act -eq 'START') {
      try { Start-Instance $launch[$cid]; Write-Host "    STARTED $cid"; Log "STARTED $cid"; if ($event -eq 'CRASH') { $cCrash++; Alert ("Client $cid ($($c.name)) tat ngoai y muon - da tu dong bat lai") } }
      catch { Write-Host "    START FAIL $cid : $_"; Log "START FAIL $cid : $_"; $cFail++; Alert ("Client $cid ($($c.name)) KHONG the bat lai: $_") }
    }
    elseif ($act -eq 'STOP') { try { Stop-Instance $runningPid; Write-Host "    STOPPED $cid (pid $runningPid)"; Log "STOPPED $cid pid=$runningPid" } catch { Write-Host "    STOP FAIL $cid : $_"; Log "STOP FAIL $cid : $_" } }
    elseif ($act -eq 'ZOMBIE_RESTART') {
      $entry = $zr[$cid]
      $do = $true; $giveup = $false
      if ($entry) {
        if ($entry.broken) { $do = $false }
        elseif ((Get-Date).Subtract($entry.last).TotalMinutes -lt $zombieCooldownMin) { $do = $false }
        elseif ($entry.attempts -ge $zombieMaxAttempts) {
          $do = $false; $giveup = $true
          $entry.broken = $true
          Alert ("Client $cid ($($c.name)) zombie lien tuc (khong ket noi game) sau $zombieMaxAttempts lan restart -> dung tu dong, can kiem tra tai khoan/scene cua client nay")
        }
      }
      if ($do) {
        try {
          if ($runningPid) { Stop-Instance $runningPid }
          Start-Instance $launch[$cid]
          $att = if ($entry) { $entry.attempts + 1 } else { 1 }
          $zr[$cid] = [ordered]@{ last = Get-Date; attempts = $att; broken = $false }
          Write-Host "    ZOMBIE-RESTART $cid (attempt $att)"; Log "ZOMBIE-RESTART $cid attempt=$att"
          Alert ("Client $cid ($($c.name)) zombie (process song nhung chua ket noi game) - da tu dong khoi dong lai (lan $att)")
        } catch { Write-Host "    ZOMBIE-RESTART FAIL $cid : $_"; Log "ZOMBIE-RESTART FAIL $cid : $_"; $cFail++; Alert ("Client $cid ($($c.name)) zombie nhung KHONG the restart: $_") }
      } else {
        if (-not $giveup) { Write-Host "    ZOMBIE $cid (cooldown, skip restart)"; Log "ZOMBIE $cid cooldown skip" }
      }
    }
  } else {
    if ($event -eq 'CRASH') { Alert ("[DRYRUN] Client $cid ($($c.name)) dang tat ngoai y muon (se bat lai khi -Apply)") }
    elseif ($act -eq 'ZOMBIE_RESTART') { Alert ("[DRYRUN] Client $cid ($($c.name)) zombie (process song nhung chua ket noi game) - se restart khi -Apply") }
  }

  # expected next-running state
  $next = if ($act -eq 'START') { $true } elseif ($act -eq 'STOP') { $false } else { $running }
  $newRunning[$cid] = $next
}

# Persist state
[ordered]@{ ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'); running = $newRunning } | ConvertTo-Json -Compress | Set-Content $StatePath -Encoding UTF8

# Persist zombie recovery state
if ($zr.Count -eq 0) { if (Test-Path $zrPath) { Remove-Item $zrPath -Force } }
else { $zr | ConvertTo-Json | Set-Content $zrPath -Encoding UTF8 }

Log ("SUMMARY start=$cStart stop=$cStop none=$cNone skip=$cSkip crash=$cCrash fail=$cFail zombie=$cZombie Apply=$Apply")
if (-not $Apply) { Write-Host "`nDRY-RUN: nothing changed. Re-run with -Apply to actually start/stop instances." }
