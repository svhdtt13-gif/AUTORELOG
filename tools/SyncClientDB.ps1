#SyncClientDB.ps1 - update client_database.json from live remote data
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$config = Get-Content "$dir\config.json" -Raw | ConvertFrom-Json
$live = Get-Content "$dir\client_names_live.json" -Raw | ConvertFrom-Json -ErrorAction Stop

$fixedIds = @{}
foreach ($e in $config.emulators.fixed) { $fixedIds[$e.client] = $true }

$clients = @()
foreach ($entry in ($live | Sort-Object idx)) {
    $client = ($entry.client -split ':')[-1]
    $group = if ($fixedIds.ContainsKey($client)) { "fixed" } else { "scheduled" }
    $clients += [PSCustomObject]@{
        idx    = [int]$entry.idx
        client = $client
        name   = $entry.name.Trim()
        status = $entry.state
        group  = $group
    }
}

$db = [PSCustomObject]@{
    clients     = $clients
    lastUpdated = (Get-Date -Format "yyyy-MM-dd")
}
$db | ConvertTo-Json -Depth 5 | Set-Content "$dir\client_database.json" -Encoding UTF8

Write-Host "=== client_database.json UPDATED ===" -ForegroundColor Green
foreach ($c in $clients) {
    $color = if ($c.status -eq "running") { "Green" } else { "DarkGray" }
    Write-Host ("  {0,2}  {1,-10}  {2,-22}  {3,-8}  {4}" -f $c.idx, $c.client, $c.name, $c.status, $c.group) -ForegroundColor $color
}