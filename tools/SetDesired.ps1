#SetDesired.ps1 - set desired (status) per client for batch deploy
# Usage: powershell -File SetDesired.ps1 -Set "6:off,9:off,45:on,46:on"
param(
    [Parameter(Mandatory=$true)][string]$Set
)
$ErrorActionPreference = "Stop"
$dbPath = "C:\Users\ADMIN\Documents\ai tool\tools\client_database.json"
$db = Get-Content $dbPath -Raw | ConvertFrom-Json
$map = @{}
foreach ($e in ($Set -split ',')) {
    $parts = $e.Trim() -split ':'
    $map[[int]$parts[0]] = if ($parts[1] -eq 'on') { 'running' } else { 'offline' }
}
foreach ($c in $db.clients) {
    if ($map.ContainsKey([int]$c.idx)) { $c.status = $map[[int]$c.idx] }
}
$db.lastUpdated = (Get-Date -Format "yyyy-MM-dd")
$db | ConvertTo-Json -Depth 5 | Set-Content $dbPath -Encoding UTF8
Write-Host "Desired set:" -ForegroundColor Cyan
foreach ($c in $db.clients) { if ($map.ContainsKey([int]$c.idx)) { Write-Host ("  row {0,2} {1,-10} -> {2}" -f $c.idx, $c.client, $c.status) -ForegroundColor White } }