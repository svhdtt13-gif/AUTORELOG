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

# Chuẩn hóa identity client từ object bất kỳ (master client / merged / registry)
function script:Resolve-ClientId {
  param($Client)
  if ($Client.clientId) { return [string]$Client.clientId }
  if ($Client.client)   { return [string]$Client.client }
  if ($Client.id)       { return [string]$Client.id }
  return $null
}

# Policy từ group (plan §16, dulieu §16)
# Ưu tiên: field policy (nếu master có) -> client_68 / name 'Ghost Story PC*' -> group
function Get-ClientPolicy {
  param($Client)
  if ($null -ne $Client.policy -and [string]$Client.policy -ne '') { return [string]$Client.policy }
  $cid  = script:Resolve-ClientId $Client
  $name = [string]$Client.name
  if ($cid -eq 'client_68' -or $name -like '*Ghost Story PC*') { return 'orphan' }
  switch ([string]$Client.group) {
    'fixed' { return 'fixed' }
    'none'  { return 'none' }
    default { return 'scheduled' }
  }
}

# Thời gian hiện tại theo timezone của group (plan feedback: Asia/Ho_Chi_Minh).
# Windows dùng 'SE Asia Standard Time'; Linux/.NET Core dùng 'Asia/Ho_Chi_Minh'.
function Get-NowInTz {
  param([string]$TzId = 'Asia/Ho_Chi_Minh')
  try {
    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($TzId)
  } catch {
    try { $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById('SE Asia Standard Time') }
    catch { return [System.DateTime]::Now }
  }
  return [System.TimeZoneInfo]::ConvertTime([System.DateTime]::UtcNow, $tz)
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

# Tính desiredState từ policy + cửa sổ lịch + thời gian hiện tại (theo timezone group)
function Get-DesiredState {
  param($Client, $Windows, $Now = (Get-NowInTz))
  $policy = Get-ClientPolicy $Client
  switch ($policy) {
    'fixed'    { return 'running' }   # always-on, không auto-stop
    'none'     { return 'ignore' }   # không nằm trong scheduler
    'orphan'   { return 'blocked' }  # hard-block mọi control (plan B6)
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

# B3 — map key -> clientId qua snapshot (giả thuyết key = root/<sess>#<idx>).
# KHÔNG hardcode key; luôn resolve qua idx của snapshot hiện tại.
function Resolve-KeyToClient {
  param([string]$Key, $Runtime)
  if ($Key -match '#(\d+)$') {
    $idx = [int]$Matches[1]
    $hit = @($Runtime) | Where-Object { [int]$_.idx -eq $idx } | Select-Object -First 1
    if ($hit) { return $hit.clientId }
  }
  return $null
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
    $pol = Get-ClientPolicy $c
    # orphan: client_68 / 'Ghost Story PC*' PHẢI group=none
    if ($pol -eq 'orphan') {
      if ($g -ne 'none') { $rep.errors.Add("ORPHAN $($c.client) MUST be group=none (found '$g')") }
      else { $rep.warnings.Add("ORPHAN $($c.client) group=none -> scheduler hard-block (correct)") }
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

# --- Process / connection liveness (local PC control) ---
# Trả process object nếu có qnyh.exe mang -instance:$cid (dùng để lấy CreationDate, pid)
function Get-InstanceProcess {
  param([string]$cid)
  $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
  foreach ($p in $procs) {
    if ($p.CommandLine -and (($p.CommandLine -split '\s+') -contains "-instance:$cid")) { return $p }
  }
  return $null
}

# Đã THỰC SỰ kết nối vào game chưa? (loại trừ process zombie)
# process sống VÀ (TCP established đến cổng game world 30000/30001 HOẶC title cửa sổ chứa 'Server [')
function Test-InstanceConnected {
  param([string]$cid, [int[]]$gamePorts = @(30000, 30001))
  $p = Get-InstanceProcess $cid
  if (-not $p) { return $false }
  try { $title = (Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue).MainWindowTitle } catch { $title = '' }
  if ($title -and $title -like '*Server *') { return $true }
  try {
    $conns = Get-NetTCPConnection -OwningProcess $p.ProcessId -ErrorAction SilentlyContinue |
      Where-Object { $_.State -eq 'Established' -and $gamePorts -contains $_.RemotePort }
    if ($conns) { return $true }
  } catch { }
  return $false
}

Export-ModuleMember -Function ConvertFrom-ScrList, Get-ClientPolicy, Get-NowInTz, Get-ScheduleWindows, Get-DesiredState, Merge-MasterRuntime, Resolve-KeyToClient, Test-MasterModel, Get-InstanceProcess, Test-InstanceConnected
