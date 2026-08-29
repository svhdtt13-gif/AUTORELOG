# MonitorActive.ps1 — luôn theo dõi thực tế, chủ động mở theo lịch
# Chạy liên tục (loop 60s) hoặc một lần. Dùng quick_monitor.bat để khởi động nền.
param([switch]$Continuous)
$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$dbPath = "$dir\client_database.json"
$statePath = "$dir\cache\cycle_state.json"

# Xác định nhóm mục tiêu theo giờ thực
$now = Get-Date; $nowMin = ($now.Hour * 60) + $now.Minute
$slots = @((Get-Content "$dir\config.json" -Raw | ConvertFrom-Json).schedule | Sort-Object { [int]([datetime]::ParseExact($_.time,'HH:mm',$null).ToString('HHmm')) })
$n = $slots.Count; $slotMins = @(); foreach ($s in $slots) { $st = [datetime]::ParseExact($s.time,'HH:mm',$null); $slotMins += ($st.Hour*60)+$st.Minute }
$targetIdx = -1
for ($i=0; $i -lt $n; $i++) { if ($nowMin -ge $slotMins[$i]) { $targetIdx = $i } }
if ($targetIdx -lt 0) { $targetIdx = $n - 1 }
$tar = $slots[$targetIdx]; $tk = $tar.time

# Đọc DB
$db = Get-Content $dbPath -Raw | ConvertFrom-Json
# Map tên -> idx (từ alias)
$alias = @{"HANMI"="client_41";"Ahihi10"="client_42";"Ahihi6"="client_43";"Ahihi8"="client_44";"Ahihi9"="client_45";"MachNhi"="client_46";"DoanVanThu"="client_47";"LieuAnh"="client_48";"BinhDuc"="client_49";"DieuLinh"="client_50";"khoqua08"="client_2";"khoqua07"="client_5";"Me"="client_6";"khoqua09"="client_7";"khoqua10"="client_8";"NA"="client_31";"COC"="client_32";"XOAI"="client_33";"CHUOI"="client_34";"CAM"="client_35"}
$clientToIdx = @{}; foreach ($c in $db.clients) { $clientToIdx[$c.client] = [int]$c.idx }
function R($name) { if ($alias.ContainsKey($name)) { return $clientToIdx[$alias[$name]] } elseif ($name -match '^client_') { return $clientToIdx[$name] } else { return $clientToIdx[$name] } }

$openIdx = @(); foreach ($nm in $tar.open) { $openIdx += (R $nm) }
$closeIdx = @(); foreach ($nm in $tar.close) { $closeIdx += (R $nm) }

# Kiểm tra qnyh của nhóm mở
$qOpen = @(Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match 'client_(31|32|33|34|35)' })
$missing = @(); foreach ($idx in $openIdx) { $cid = $db.clients | Where-Object { [int]$_.idx -eq $idx }; if ($cid) { $cmd = (Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match [regex]::Escape($cid.client) } | Measure-Object).Count; if ($cmd -lt 1) { $missing += $cid.client } } }

if ($missing.Count -gt 0 -or $qOpen.Count -lt 5) {
    Write-Host "[MONITOR $tk] Nhóm chưa mở hoặc thiếu qnyh: $($missing -join ', ') | qnyh=$($qOpen.Count)" -ForegroundColor Yellow
    # Sửa DB thành running cho nhóm mở
    foreach ($cid in $missing) { $c = $db.clients | Where-Object { $_.client -eq $cid }; if ($c) { $c.status = 'running'; Write-Host "  DB: $cid -> running" } }
    $db | ConvertTo-Json -Depth 5 | Set-Content $dbPath -Encoding UTF8
    # Log
    Add-Content "$dir\cache\cycle.log" ("["+ (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + "] MONITOR $tk ACTIVE: sửa DB + cần khởi động qnyh")
    # Thử mở qua OpenTogether nếu có thể (tùy session)
    $env:AGROWS = ($openIdx -join ',')
    $env:AGMIN = 3
    Write-Host "[MONITOR $tk] Đã cập nhật DB -> chạy OpenTogether (nếu session OK) ..."
    try { Start-Process -FilePath "powershell" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File', "$dir\OpenTogether.ps1"') -WindowStyle Hidden -PassThru | Out-Null } catch {}
} else {
    Write-Host "[MONITOR $tk] Nhóm $tk OK: qnyh=$($qOpen.Count)/5, DB running" -ForegroundColor Green
}
# Liên tục theo thời gian thực: nếu có cờ Continuous, lặp lại sau 30 giây
if ($Continuous) {
    Write-Host "[MONITOR] Chế độ liên tục — kiểm tra lại sau 30s..." -ForegroundColor Cyan
    while ($true) {
        Start-Sleep -Seconds 30
        Write-Host "[MONITOR] Kiểm tra lại..." -ForegroundColor DarkGray
        # Chạy lại toàn bộ logic (tái sử dụng script qua Invoke-Expression hoặc gọi lại)
        # Để đơn giản: gọi lại chính script này với -Continuous
        Start-Process -FilePath "powershell" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',"$PSScriptRoot\MonitorActive.ps1","-Continuous") -WindowStyle Hidden | Out-Null
        break
    }
}
