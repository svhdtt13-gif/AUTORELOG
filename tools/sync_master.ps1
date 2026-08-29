$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$master = Get-Content "$dir\clients_master.json" -Raw | ConvertFrom-Json

$alias = @{
  "HANMI"="client_41";"Ahihi10"="client_42";"Ahihi6"="client_43";"Ahihi8"="client_44";"Ahihi9"="client_45";
  "MachNhi"="client_46";"DoanVanThu"="client_47";"LieuAnh"="client_48";"BinhDuc"="client_49";"DieuLinh"="client_50";
  "khoqua08"="client_2";"khoqua07"="client_5";"Me"="client_6";"khoqua09"="client_7";"khoqua10"="client_8";
  "NA"="client_31";"COC"="client_32";"XOAI"="client_33";"CHUOI"="client_34";"CAM"="client_35"
}
$revName = @{}; foreach ($k in $alias.Keys) { $revName[$alias[$k]] = $k }

# current db to preserve idx / status
$curDb = Get-Content "$dir\client_database.json" -Raw | ConvertFrom-Json
$idxMap = @{}; $statusMap = @{}
foreach ($c in $curDb.clients) { $idxMap[$c.client] = [int]$c.idx; $statusMap[$c.client] = $c.status }

# build clients output for db.json
$outClients = @()
foreach ($mc in $master.clients) {
  if ($mc.group -eq 'none' -or [string]::IsNullOrWhiteSpace($mc.group)) { continue }
  $cl = $mc.client
  $outClients += [pscustomobject]@{
    idx = if ($idxMap.ContainsKey($cl)) { $idxMap[$cl] } else { $outClients.Count }
    client = $cl
    name = if ($mc.name) { $mc.name } else { if($revName.ContainsKey($cl)){$revName[$cl]}else{$cl} }
    status = if ($statusMap.ContainsKey($cl)) { $statusMap[$cl] } else { "offline" }
    group = $mc.group
  }
}
$dbObj = [pscustomobject]@{ lastUpdated = (Get-Date -Format "yyyy-MM-dd"); clients = $outClients }
[System.IO.File]::WriteAllText("$dir\client_database.json", ($dbObj | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

# build schedule for config.json
$schedOut = @()
$n = $master.schedule.Count
for ($i = 0; $i -lt $n; $i++) {
  $g = $master.schedule[$i].group
  $time = $master.schedule[$i].time
  $openClients = @($master.clients | Where-Object { $_.group -eq $g } | ForEach-Object { $_.client })
  $prev = $master.schedule[($i - 1 + $n) % $n].group
  $closeClients = @($master.clients | Where-Object { $_.group -eq $prev } | ForEach-Object { $_.client })
  $openNames = @($openClients | ForEach-Object { if($revName.ContainsKey($_)){$revName[$_]}else{$_} })
  $closeNames = @($closeClients | ForEach-Object { if($revName.ContainsKey($_)){$revName[$_]}else{$_} })
  $schedOut += [pscustomobject]@{ time = $time; open = $openNames; close = $closeNames }
}

$fixedClients = @($master.clients | Where-Object { $_.group -eq 'fixed' } | ForEach-Object { $_.client })
$cfg = Get-Content "$dir\config.json" -Raw | ConvertFrom-Json
$cfg.schedule = $schedOut
$cfg.emulators.fixed = [pscustomobject]@{ client = $fixedClients }
[System.IO.File]::WriteAllText("$dir\config.json", ($cfg | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

# regenerate CSV mirror
$lines = @("client,name,group,slot_time")
foreach ($mc in $master.clients) { $lines += "$($mc.client),$($mc.name),$($mc.group),$($mc.slot)" }
Set-Content "$dir\clients_master.csv" -Value $lines -Encoding UTF8

Write-Host "sync_master: regenerated client_database.json, config.json, clients_master.csv"
