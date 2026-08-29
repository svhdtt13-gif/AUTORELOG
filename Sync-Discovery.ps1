param(
  [string]$MasterPath   = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$RuntimePath  = (Join-Path $PSScriptRoot 'scr_list_sample.json'),
  [string]$RegistryPath = (Join-Path $PSScriptRoot 'runtime_registry.json'),
  [string]$ReportPath   = (Join-Path $PSScriptRoot 'discovery_report.txt')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Core.psm1') -Force

$master  = Get-Content $MasterPath  -Raw | ConvertFrom-Json
$runtime = ConvertFrom-ScrList (Get-Content $RuntimePath -Raw | ConvertFrom-Json)
$windows = Get-ScheduleWindows $master

Write-Host "Loaded master ($($master.clients.Count) clients) + runtime ($($runtime.Count) instances)."

$merged = Merge-MasterRuntime -Master $master -Runtime $runtime

$registry = [ordered]@{
  generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  windows    = $windows
  clients    = @()
}

foreach ($m in $merged) {
  $client = [pscustomobject]@{
    clientId        = $m.clientId
    name            = $m.name
    group           = $m.group
    policy          = $m.policy
    masterPresent   = $m.masterPresent
    runtimePresent  = $m.runtimePresent
    runtimeState    = $m.runtimeState
    cap             = $m.cap
    idx             = $m.idx
    identityVerified = $m.identityVerified
    orphan          = $m.orphan
    classification  = $m.classification
    desiredState    = $null
    lastAction      = $null
    lastError       = $null
  }
  if ($m.masterPresent) {
    $client.desiredState = Get-DesiredState -Client @{ clientId = $m.clientId; name = $m.name; group = $m.group; policy = $m.policy } -Windows $windows
  } else {
    $client.desiredState = 'unknown'
  }
  $registry.clients += $client
}

$registry | ConvertTo-Json -Depth 6 | Set-Content -Path $RegistryPath -Encoding UTF8

# Build human report
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("DISCOVERY / SYNC REPORT  -  $(Get-Date)")
[void]$sb.AppendLine("master clients : $($master.clients.Count)")
[void]$sb.AppendLine("runtime instances: $($runtime.Count)")
[void]$sb.AppendLine()
[void]$sb.AppendLine("SCHEDULE WINDOWS:")
foreach ($w in $windows) {
  $tag = if ($w.wrapNextDay) { ' (+1d)' } else { '' }
  [void]$sb.AppendLine("  $($w.group): $($w.open) -> $($w.close)$tag  ($($w.durationMin)m)")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine("CLIENT RECONCILIATION:")
foreach ($c in $registry.clients) {
  [void]$sb.AppendLine(("  {0,-12} {1,-16} grp={2,-6} pol={3,-9} cls={4,-16} rt={5,-8} desired={6}" -f `
    $c.clientId, $c.name, $c.group, $c.policy, $c.classification, $c.runtimeState, $c.desiredState))
}
[void]$sb.AppendLine()
$counts = $registry.clients | Group-Object classification | ForEach-Object { "$($_.Name)=$($_.Count)" }
[void]$sb.AppendLine("SUMMARY: " + ($counts -join ', '))

Set-Content -Path $ReportPath -Value $sb.ToString() -Encoding UTF8
Write-Host $sb.ToString()
Write-Host "Registry written -> $RegistryPath"
