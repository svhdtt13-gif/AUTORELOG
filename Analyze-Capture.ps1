param(
  [string]$CapturePath = (Join-Path $PSScriptRoot 'capture.jsonl'),
  [string]$ReportPath  = (Join-Path $PSScriptRoot 'capture_analysis.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Ws.psm1') -Force

if (-not (Test-Path $CapturePath)) { Write-Error "Thiếu $CapturePath. Chạy Capture-Ws.ps1 trước."; exit 2 }

$lines = Get-Content $CapturePath -Encoding UTF8
$snapshots = @()   # {ts, map: name->clientId, keys: idx->key, epochs: idx->epoch}
$reconnects = @() # {tsReconnect, tsOpen, downSec}
$lastOpen = $null

foreach ($l in $lines) {
  try { $e = $l | ConvertFrom-Json } catch { continue }
  $ts = [datetime]::Parse($e.ts, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
  if ($e.dir -eq 'recv') {
    $insts = Get-ScrInstances $e.msg
    if ($insts.Count -gt 0) {
      $map = @{}; $keys = @{}; $epochs = @{}
      foreach ($i in $insts) {
        if ($i.name) { $map[[string]$i.name] = $i.clientId }
        if ($i.idx -ne $null) {
          if ($i.key)  { $keys[[int]$i.idx]  = $i.key }
          if ($i.epoch -ne $null) { $epochs[[int]$i.idx] = $i.epoch }
        }
      }
      $snapshots += [pscustomobject]@{ ts = $ts; map = $map; keys = $keys; epochs = $epochs }
    }
  } elseif ($e.dir -eq 'system') {
    $m = $e.msg | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($m.event -eq 'open') { if ($lastOpen -and $reconnects.Count -gt 0) { $reconnects[-1].tsOpen = $ts; $reconnects[-1].downSec = [math]::Round(($ts - $reconnects[-1].tsReconnect).TotalSeconds, 1) } ; $lastOpen = $ts }
    if ($m.event -eq 'reconnect') { $reconnects += [pscustomobject]@{ tsReconnect = $ts; tsOpen = $null; downSec = $null } }
  }
}

# --- B1: stable client_id across snapshots (match by name) ---
$b1 = [ordered]@{}
$names = @($snapshots | ForEach-Object { $_.map.Keys } | Sort-Object -Unique)
foreach ($nm in $names) {
  $ids = @($snapshots | ForEach-Object { if ($_.map.ContainsKey($nm)) { $_.map[$nm] } })
  $uniq = @($ids | Sort-Object -Unique)
  if ($uniq.Count -eq 1) { $cls = 'STABLE' }
  elseif ($uniq.Count -gt 1) { $cls = 'REGENERATED' }
  else { $cls = 'UNKNOWN' }
  $b1[$nm] = [pscustomobject]@{ name = $nm; clientIds = $uniq; classification = $cls }
}

# --- B3: key / epoch semantics ---
$b3 = [ordered]@{}
$idxs = @($snapshots | ForEach-Object { $_.keys.Keys } | Sort-Object -Unique)
$keyHasIdx = $true; $keySamples = @()
foreach ($ix in $idxs) {
  $ks = @($snapshots | ForEach-Object { if ($_.keys.ContainsKey($ix)) { $_.keys[$ix] } } | Sort-Object -Unique)
  if ($ks.Count -gt 0) {
    $first = $ks[0]
    if ($first -notmatch "#$ix`$") { $keyHasIdx = $false }
    $keySamples += [pscustomobject]@{ idx = $ix; keys = $ks }
  }
}
$epochChanges = @()
foreach ($ix in @($snapshots | ForEach-Object { $_.epochs.Keys } | Sort-Object -Unique)) {
  $es = @($snapshots | ForEach-Object { if ($_.epochs.ContainsKey($ix)) { $_.epochs[$ix] } } | Sort-Object -Unique)
  if ($es.Count -gt 1) { $epochChanges += [pscustomobject]@{ idx = $ix; epochs = $es } }
}
$b3['keyContainsIdx'] = $keyHasIdx
$b3['keySamples'] = $keySamples
$b3['epochChangesAcrossSnapshots'] = $epochChanges

# --- B7: heartbeat interval + reconnect downtime ---
$snapTs = @($snapshots | ForEach-Object { $_.ts })
$ivals = @()
for ($i = 1; $i -lt $snapTs.Count; $i++) { $ivals += [math]::Round(($snapTs[$i] - $snapTs[$i-1]).TotalSeconds, 1) }
$b7 = [pscustomobject]@{
  snapshotCount = $snapTs.Count
  heartbeatSec_min = if ($ivals.Count) { ($ivals | Measure-Object -Min).Minimum } else { $null }
  heartbeatSec_avg = if ($ivals.Count) { [math]::Round(($ivals | Measure-Object -Average).Average, 1) } else { $null }
  heartbeatSec_max = if ($ivals.Count) { ($ivals | Measure-Object -Max).Maximum } else { $null }
  reconnectCount   = $reconnects.Count
  reconnectDownSec = @($reconnects | Where-Object { $null -ne $_.downSec } | ForEach-Object { $_.downSec })
}

$report = [ordered]@{
  generatedAt   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  snapshotCount = $snapshots.Count
  B1_stableId   = $b1
  B3_keyEpoch   = $b3
  B7_heartbeat  = $b7
  gates = [ordered]@{
    B1 = if ($snapshots.Count -lt 2) { 'INSUFFICIENT_DATA' } elseif ((@($b1.Values | Where-Object { $_.classification -ne 'STABLE' }).Count) -eq 0) { 'PASS' } else { 'REGENERATED/FAIL' }
    B3 = if ($keySamples.Count -eq 0) { 'INSUFFICIENT_DATA' } else { 'PARTIAL' }
    B7 = if ($snapshots.Count -lt 2) { 'INSUFFICIENT_DATA' } else { 'MEASURED' }
  }
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $ReportPath -Encoding UTF8

Write-Host "=== CAPTURE ANALYSIS ==="
Write-Host "Snapshots: $($snapshots.Count)"
Write-Host "`nB1 stable client_id:"
foreach ($k in $b1.Keys) { Write-Host ("  {0,-16} {1,-12} ids={2}" -f $k, $b1[$k].classification, ($b1[$k].clientIds -join ',')) }
Write-Host "`nB3 key contains idx: $($b3.keyContainsIdx) | epoch changes: $($epochChanges.Count)"
Write-Host "`nB7 heartbeat sec (min/avg/max): $($b7.heartbeatSec_min)/$($b7.heartbeatSec_avg)/$($b7.heartbeatSec_max) | reconnects: $($b7.reconnectCount)"
Write-Host "`nGates: B1=$($report.gates.B1) B3=$($report.gates.B3) B7=$($report.gates.B7)"
Write-Host "Detail -> $ReportPath"
