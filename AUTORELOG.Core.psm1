# AUTORELOG.Core.psm1
# Module mô hình 3 lớp: MASTER / RUNTIME / CONTROL
# Chỉ chứa logic thuần (không kết nối mạng). Dùng bởi Sync-Discovery, B1-B7-Validate, Agent.

$ErrorActionPreference = 'Stop'

function script:ToMin { param([string]$t) $h, $m = $t -split ':'; return [int]$h * 60 + [int]$m }

# Chuẩn hóa instance từ scr_list_res: bỏ prefix transport "0:" -> client_14
function ConvertFrom-ScrList {
  param($Raw)
  $arr = if ($Raw -is [System.Collections.IEnumerable] -and -not ($Raw -is [string])) {
    if ($Raw.instances) { @($Raw.instances) } else { @($Raw) }
  } elseif ($Raw.instances) { @($Raw.instances) } else { @($Raw) }
  $out = @()
  foreach ($i in $arr) {
    $rid = [string]$i.id
    $cid = if ($rid -match ':(.+)$') { $Matches[1] } else { $rid }
    $out += [pscustomobject]@{
      rawId        = $rid
      clientId     = $cid
      idx          = $i.idx
      name         = $i.name
      state        = [string]$i.state
      cap          = [string]$i.cap
      capAge       = $i.capAge
    }
  }
  return $out
}

# Policy từ group (plan §16, dulieu §16)
function Get-ClientPolicy {
  param($Client)
  if ($Client.client -eq 'client_68') { return 'orphan' }
  switch ([string]$Client.group) {
    'fixed' { return 'fixed' }
    'none'  { return 'none' }
    default { return 'scheduled' }
  }
}

# Suy cửa sổ lịch từ schedule[] (open = time, close = group kế tiếp, wrap nếu cần)
function Get-ScheduleWindows {
  param($Master)
  $ordered = @($Master.schedule) | Sort-Object { script:ToMin $_.time }
  $n = $ordered.Count; $w = @()
  for ($i = 0; $i -lt $n; $i++) {
    $cur = $ordered[$i]; $nxt = $ordered[($i + 1) % $n]
    $o = script:ToMin $cur.time; $c = script:ToMin $nxt.time; $wrap = $false
    if ($c -le $o) { $c += 1440; $wrap = $true }
    if ($c -eq $o) { throw "Group $($cur.group) has zero-length window" }
    $w += [pscustomobject]@{
      group       = $cur.group
      open        = $cur.time
      close       = $nxt.time
      wrapNextDay = $wrap
      durationMin = ($c - $o)
    }
  }
  return $w
}

# Tính desiredState từ policy + cửa sổ lịch + thời gian hiện tại
function Get-DesiredState {
  param($Client, $Windows, $Now = (Get-Date))
  $policy = Get-ClientPolicy $Client
  switch ($policy) {
    'fixed'    { return 'running' }   # always-on, không auto-stop
    'none'     { return 'ignore' }   # không nằm trong scheduler
    'orphan'   { return 'blocked' }  # hard-block mọi control
    'scheduled' {
      $win = $Windows | Where-Object { $_.group -eq [string]$Client.group }
      if (-not $win) { return 'unknown' }
      $nm = $Now.Hour * 60 + $Now.Minute
      $s = script:ToMin $win.open; $e = script:ToMin $win.close
      if ($win.wrapNextDay) { $e += 1440; if ($nm -lt $s) { $nm += 1440 } }
      if ($nm -ge $s -and $nm -lt $e) { return 'running' } else { return 'stopped' }
    }
    default { return 'unknown' }
  }
}

# Reconcile master <-> runtime (plan §7, dulieu §14)
function Merge-MasterRuntime {
  param($Master, $Runtime)
  $rtById = @{}
  foreach ($r in $Runtime) { $rtById[$r.clientId] = $r }
  $masterIds = @($Master.clients | ForEach-Object { [string]$_.client })
  $result = @()
  foreach ($c in @($Master.clients)) {
    $r = $rtById[[string]$c.client]
    $policy = Get-ClientPolicy $c
    $result += [pscustomobject]@{
      clientId        = [string]$c.client
      name            = [string]$c.name
      group           = [string]$c.group
      policy          = $policy
      masterPresent   = $true
      runtimePresent  = ($null -ne $r)
      runtimeState    = if ($r) { $r.state } else { $null }
      cap             = if ($r) { $r.cap } else { $null }
      idx             = if ($r) { $r.idx } else { $null }
      identityVerified = $false
      orphan          = ($policy -eq 'orphan')
      classification  = if (-not $r) { 'missing-in-runtime' }
                        elseif ($policy -eq 'orphan') { 'orphan' }
                        else { 'known' }
    }
  }
  # runtime có nhưng không có trong master -> new/orphan
  foreach ($r in $Runtime) {
    if ([string]$r.clientId -notin $masterIds) {
      $result += [pscustomobject]@{
        clientId        = $r.clientId
        name            = $r.name
        group           = $null
        policy          = 'unknown'
        masterPresent   = $false
        runtimePresent  = $true
        runtimeState    = $r.state
        cap             = $r.cap
        idx             = $r.idx
        identityVerified = $false
        orphan          = $false
        classification  = 'new/orphan'
      }
    }
  }
  return $result
}

# Validate master (plan §3 B4, dulieu §18/§19) - trả về report object
function Test-MasterModel {
  param($Master)
  $rep = [ordered]@{
    result = 'PASS'; totalClients = 0; totalGroups = 0
    errors = [System.Collections.Generic.List[string]]::new()
    warnings = [System.Collections.Generic.List[string]]::new()
    windows = [System.Collections.Generic.List[object]]::new()
  }
  $clients = @($Master.clients); $schedules = @($Master.schedule)
  $seen = @{}
  foreach ($c in $clients) {
    if ($seen.ContainsKey([string]$c.client)) { $rep.errors.Add("DUPLICATE client id: $($c.client)") }
    else { $seen[[string]$c.client] = $true }
  }
  $groupMembers = @{}
  foreach ($c in $clients) {
    $g = [string]$c.group
    if (-not $groupMembers.ContainsKey($g)) { $groupMembers[$g] = @() }
    $groupMembers[$g] += [string]$c.client
    if ($c.client -eq 'client_68' -or [string]$c.name -like '*Ghost Story PC*') {
      if ($g -ne 'none') { $rep.warnings.Add("ORPHAN candidate $($c.client) should be group=none") }
    }
    if ($g -eq 'fixed' -and $null -ne $c.slot) { $rep.warnings.Add("fixed $($c.client) has slot set (ignored)") }
  }
  $schedGroups = @{}
  foreach ($s in $schedules) {
    if ($schedGroups.ContainsKey($s.group)) { $rep.errors.Add("DUPLICATE schedule group: $($s.group)") }
    else { $schedGroups[$s.group] = $s.time }
    if ($s.group -notin $groupMembers.Keys) { $rep.errors.Add("schedule group $($s.group) has no clients") }
    if ([string]$s.time -notmatch '^\d{1,2}:\d{2}$') { $rep.errors.Add("schedule $($s.group) bad time '$($s.time)'") }
  }
  foreach ($g in @('none', 'fixed')) {
    if ($schedGroups.ContainsKey($g)) { $rep.errors.Add("group '$g' MUST NOT appear in schedule") }
  }
  $ordered = $schedules | Sort-Object { script:ToMin $_.time }
  $n = $ordered.Count
  for ($i = 0; $i -lt $n; $i++) {
    $cur = $ordered[$i]; $nxt = $ordered[($i + 1) % $n]
    $o = script:ToMin $cur.time; $c2 = script:ToMin $nxt.time; $wrap = $false
    if ($c2 -le $o) { $c2 += 1440; $wrap = $true }
    if ($c2 -eq $o) { $rep.errors.Add("group $($cur.group) zero-length window") }
    $rep.windows.Add([pscustomobject]@{ group = $cur.group; open = $cur.time; close = $nxt.time; wrapNextDay = $wrap; durationMin = ($c2 - $o) })
  }
  foreach ($c in $clients) {
    $g = [string]$c.group
    if ($g -match '^gr\d+$' -and $schedGroups.ContainsKey($g)) {
      if ([string]$c.slot -ne [string]$schedGroups[$g]) {
        $rep.warnings.Add("client $($c.client) slot '$($c.slot)' != group $g time '$($schedGroups[$g])'")
      }
    }
  }
  $rep.totalClients = $clients.Count
  $rep.totalGroups = $groupMembers.Keys.Count
  if ($rep.errors.Count -gt 0) { $rep.result = 'FAIL' }
  return $rep
}

Export-ModuleMember -Function ConvertFrom-ScrList, Get-ClientPolicy, Get-ScheduleWindows, Get-DesiredState, Merge-MasterRuntime, Test-MasterModel
