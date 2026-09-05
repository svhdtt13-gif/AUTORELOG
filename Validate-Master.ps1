param(
  [string]$MasterPath = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$ReportPath = (Join-Path $PSScriptRoot 'master_validation_report.json')
)
$ErrorActionPreference = 'Stop'

function ToMin { param([string]$t) $h, $m = $t -split ':'; return [int]$h * 60 + [int]$m }

$report = [ordered]@{
  file           = $MasterPath
  timestamp      = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  result         = 'UNKNOWN'
  totalClients   = 0
  totalGroups    = 0
  orphanHardBlock = $true
  errors         = [System.Collections.Generic.List[string]]::new()
  warnings       = [System.Collections.Generic.List[string]]::new()
  info           = [System.Collections.Generic.List[string]]::new()
  windows        = [System.Collections.Generic.List[object]]::new()
}

try {
  if (-not (Test-Path $MasterPath)) { throw "Master not found: $MasterPath" }
  $m = Get-Content $MasterPath -Raw | ConvertFrom-Json
} catch {
  Write-Error $_
  exit 2
}

$clients  = @($m.clients)
$schedules = @($m.schedule)

# 1) duplicate client id
$seen = @{}
foreach ($c in $clients) {
  if ($seen.ContainsKey($c.client)) { $report.errors.Add("DUPLICATE client id: $($c.client)") }
  else { $seen[$c.client] = $true }
}

# 2) per-client checks + group membership
$groupMembers = @{}
foreach ($c in $clients) {
  if (-not $c.client) { $report.errors.Add('client missing id') }
  if (-not $c.name)   { $report.warnings.Add("client $($c.client) missing name") }
  if (-not $c.group)  { $report.errors.Add("client $($c.client) missing group") }
  $g = [string]$c.group
  if ($g -notin @('fixed', 'none') -and $g -notmatch '^gr\d+$') {
    $report.warnings.Add("client $($c.client) has unusual group: $g")
  }
  if (-not $groupMembers.ContainsKey($g)) { $groupMembers[$g] = @() }
  $groupMembers[$g] += $c.client

  # orphan detection (plan B6): client_68 / 'Ghost Story PC*' MUST be group=none
  if ($c.client -eq 'client_68' -or [string]$c.name -like '*Ghost Story PC*') {
    if ($g -ne 'none') { $report.errors.Add("ORPHAN candidate $($c.client) MUST be group=none (found '$g')") }
    else { $report.info.Add("ORPHAN candidate $($c.client) correctly group=none -> scheduler hard-blocked") }
  }
  # fixed must not carry a slot (plan: always-on, no auto-stop)
  if ($g -eq 'fixed' -and $null -ne $c.slot) {
    $report.warnings.Add("fixed $($c.client) has slot set (ignored by policy)")
  }
}

# 3) schedule checks
$schedGroups = @{}
foreach ($s in $schedules) {
  if ($schedGroups.ContainsKey($s.group)) { $report.errors.Add("DUPLICATE schedule group: $($s.group)") }
  else { $schedGroups[$s.group] = $s.time }
  if ($s.group -notin $groupMembers.Keys) { $report.errors.Add("schedule group $($s.group) has no clients in master") }
  if ([string]$s.time -notmatch '^\d{1,2}:\d{2}$') { $report.errors.Add("schedule $($s.group) bad time '$($s.time)'") }
}
# none/fixed must NOT be scheduled (plan B3/B4)
foreach ($g in @('none', 'fixed')) {
  if ($schedGroups.ContainsKey($g)) { $report.errors.Add("group '$g' MUST NOT appear in schedule") }
}

# 4) derive windows (open = group time, close = next group's open, wrap if needed)
$ordered = $schedules | Sort-Object { ToMin $_.time }
$n = $ordered.Count
for ($i = 0; $i -lt $n; $i++) {
  $cur = $ordered[$i]; $nxt = $ordered[($i + 1) % $n]
  $open = ToMin $cur.time; $close = ToMin $nxt.time; $wrap = $false
  if ($close -le $open) { $close += 1440; $wrap = $true }
  if ($close -eq $open) { $report.errors.Add("group $($cur.group) has zero-length window") }
  $report.windows.Add([pscustomobject]@{
      group        = $cur.group
      open         = $cur.time
      close        = $nxt.time
      wrapNextDay  = $wrap
      durationMin  = ($close - $open)
    })
}

# 5) consistency: client slot must equal its group schedule time
foreach ($c in $clients) {
  $g = [string]$c.group
  if ($g -match '^gr\d+$' -and $schedGroups.ContainsKey($g)) {
    if ([string]$c.slot -ne [string]$schedGroups[$g]) {
      $report.warnings.Add("client $($c.client) slot '$($c.slot)' != group $g schedule time '$($schedGroups[$g])'")
    }
  }
}

# 6) summary
$report.totalClients = $clients.Count
$report.totalGroups  = $groupMembers.Keys.Count
$report.result = if ($report.errors.Count -eq 0) { 'PASS' } else { 'FAIL' }

$report | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportPath -Encoding UTF8

Write-Host "=== MASTER VALIDATION: $($report.result) ==="
Write-Host "Clients: $($report.totalClients) | Groups: $($report.totalGroups)"
Write-Host "`nWindows (derived open->close):"
foreach ($w in $report.windows) {
  $tag = if ($w.wrapNextDay) { ' (+1d)' } else { '' }
  Write-Host ("  {0}: {1} -> {2}{3}  ({4}m)" -f $w.group, $w.open, $w.close, $tag, $w.durationMin)
}
if ($report.errors)   { Write-Host "`nERRORS:";   $report.errors   | ForEach-Object { Write-Host "  [E] $_" } }
if ($report.warnings) { Write-Host "`nWARNINGS:"; $report.warnings | ForEach-Object { Write-Host "  [W] $_" } }
if ($report.info)     { Write-Host "`nINFO:";     $report.info     | ForEach-Object { Write-Host "  [i] $_" } }
if ($report.errors.Count -eq 0 -and $report.warnings.Count -eq 0) { Write-Host "`nNo issues found." }
exit $(if ($report.errors.Count -eq 0) { 0 } else { 1 })
