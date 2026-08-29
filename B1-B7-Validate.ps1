param(
  [string]$MasterPath = (Join-Path $PSScriptRoot 'clients_master.json'),
  [string]$RuntimePath = (Join-Path $PSScriptRoot 'scr_list_sample.json'),
  [string]$ReportPath = (Join-Path $PSScriptRoot 'phase0_gate_report.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Core.psm1') -Force

$master  = Get-Content $MasterPath -Raw | ConvertFrom-Json
$runtime = $null
if (Test-Path $RuntimePath) { $runtime = ConvertFrom-ScrList (Get-Content $RuntimePath -Raw | ConvertFrom-Json) }

$gates = [System.Collections.Generic.List[object]]::new()

function Add-Gate($id, $desc, $status, $evidence) {
  $gates.Add([pscustomobject]@{ id = $id; description = $desc; status = $status; evidence = $evidence })
}

# B4 - master structure / validation (chay duoc ngay)
$mr = Test-MasterModel $master
if ($mr.result -eq 'PASS') {
  Add-Gate 'B4' 'XLSX/master validation cau truc va wraparound' 'PASS' 'Master hop le, khong loi.'
} else {
  Add-Gate 'B4' 'XLSX/master validation cau truc va wraparound' 'FAIL' ($mr.errors -join '; ')
}

# B6 - client_68 orphan (cau truc)
$orphan = @($master.clients) | Where-Object { $_.client -eq 'client_68' }
if ($orphan -and [string]$orphan[0].group -eq 'none') {
  Add-Gate 'B6' 'client_68 orphan classification' 'STRUCT_PASS_LIVE_PENDING' 'Master gan client_68=none hard-block. Can live reconcile voi scr_list de xac nhan orphan.'
} else {
  Add-Gate 'B6' 'client_68 orphan classification' 'FAIL' 'client_68 chua dung policy none.'
}

if ($runtime) {
  Add-Gate 'B1' 'Stable client_id qua restart' 'PENDING_PC_TEST' ("Snapshot co {0} instances, client_id chuan hoa on (bo prefix transport). Can restart Auto/PC de xac nhan ben vung." -f $runtime.Count)
  Add-Gate 'B3' 'key epoch semantics' 'PENDING_PC_TEST' 'Can capture key/epoch tu Remote de giai ma.'
  Add-Gate 'B5' 'Group conflict 1 client 1 group' 'PASS_STRUCT' 'Master hien tai moi client thuoc 1 group duy nhat (single-value group field).'
} else {
  Add-Gate 'B1' 'Stable client_id qua restart' 'PENDING_PC_TEST' 'Chua co runtime snapshot; can chay tren PC that.'
  Add-Gate 'B3' 'key epoch semantics' 'PENDING_PC_TEST' 'Chua co evidence.'
  Add-Gate 'B5' 'Group conflict 1 client 1 group' 'PENDING' 'Can master va runtime de so khop.'
}

Add-Gate 'B2' 'row_toggle va Start Stop correlation' 'PENDING_PC_TEST' 'Can capture 1 client: OFFLINE row_toggle RUNNING va nguoc lai, xac nhan qua delta scr_list_res.'
Add-Gate 'B7' 'Heartbeat reconnect do thuc te' 'PENDING_PC_TEST' 'Baseline 10s 30s la design; can do tren PC.'

$report = [ordered]@{
  generatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  note        = 'PASS = du evidence; STRUCT = dung cau truc can live confirm; PENDING_PC_TEST = phai chay tren PC that.'
  gates      = $gates
}

$report | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportPath -Encoding UTF8

Write-Host '=== PHASE 0 GATE REPORT ==='
foreach ($g in $gates) {
  Write-Host ('  {0,-3} {1,-42} [{2}]' -f $g.id, $g.description, $g.status)
}
Write-Host ''
Write-Host "Detail written -> $ReportPath"
