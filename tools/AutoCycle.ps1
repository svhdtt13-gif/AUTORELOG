#AutoCycle.ps1 - run the full 4-slot schedule automatically at real clock times
# Reads config.json schedule. For each slot: CLOSE group fully (toggle-off checked + kill local), then OPEN group simultaneously (row_toggle together on one connection).
# Runs as a daemon loop; each slot executes once per day (state tracked in cache/cycle_state.json).
# Usage: powershell -ExecutionPolicy Bypass -File AutoCycle.ps1   (run in background / Task Scheduler)   [-Now]
$ErrorActionPreference = "Continue"
trap { Log ("TRAP @ line $($_.InvocationInfo.ScriptLineNumber) : " + $_.Exception.Message); continue }
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$log = "$dir\cache\cycle.log"
function Log($m) { Add-Content $log ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $m) }

if ($args -contains "-Now") {
    Write-Host "[-Now] run slots whose time has passed today once, then exit" -ForegroundColor Cyan
}

$cfg = Get-Content "$dir\config.json" -Raw | ConvertFrom-Json
$db  = Get-Content "$dir\client_database.json" -Raw | ConvertFrom-Json

# name -> client (config uses ASCII names; DB uses client_XX)
$alias = @{
  "HANMI"  = "client_41"; "Ahihi10" = "client_42"; "Ahihi6" = "client_43"; "Ahihi8" = "client_44"; "Ahihi9" = "client_45"
  "MachNhi"= "client_46"; "DoanVanThu" = "client_47"; "LieuAnh" = "client_48"; "BinhDuc" = "client_49"; "DieuLinh" = "client_50"
  "khoqua08" = "client_2"; "khoqua07" = "client_5"; "Me" = "client_6"; "khoqua09" = "client_7"; "khoqua10" = "client_8"
  "NA" = "client_31"; "COC" = "client_32"; "XOAI" = "client_33"; "CHUOI" = "client_34"; "CAM" = "client_35"
}
$clientToIdx = @{}; foreach ($c in $db.clients) { $clientToIdx[$c.client] = [int]$c.idx }
function Resolve-Idx($name) { if ($alias.ContainsKey($name)) { return $clientToIdx[$alias[$name]] }; if ($name -match '^client_') { return $clientToIdx[$name] }; return $clientToIdx[$name] }
# SAFETY: fixed (always-on) clients may never be toggled off / killed with groups
$fixedIdx = @{}
foreach ($fx in $cfg.emulators.fixed) { $fixedIdx[$clientToIdx[$fx.client]] = $true }
function Filter-Fixed($rows) { @($rows | Where-Object { -not $fixedIdx.ContainsKey($_) }) }

# ---- websocket helpers (proven patterns) ----
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
function New-WS {
    $w = New-Object System.Net.WebSockets.ClientWebSocket
    $w.Options.SetRequestHeader("Authorization", "Bearer $token")
    $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $w.ConnectAsync($uri, $ct).Wait(); $w
}
function SW($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function DR($ws, [int]$secs) {
    $t = [DateTime]::UtcNow.AddSeconds($secs); $o = @()
    while ([DateTime]::UtcNow -lt $t -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(400)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $o += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $o
}
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Connect-Snap {
    $w = New-WS; SW $w '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; SW $w '{"t":"launch","product_id":73}'
    $snap = $null; $t0 = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $t0 -and $w.State -eq "Open" -and -not $snap) {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $w.State -eq "Open") {
                $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
            }
            if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { $snap = $p } }
            $ms.Dispose()
        } catch { break }
    }
    if (-not $snap) { $w.Dispose(); return $null }
    return @{ ws = $w; snap = $snap }
}
function RowChecked($snap) {
    $h = @{}
    foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { foreach ($rw in $n.rows) { $h[[int]$rw.r] = [int]$rw.checked } } }
    return $h
}
function Toggle-Rows($rows, $wantOn) {
    # returns hashtable row->true/true all ok; retries once if any act_result ok=False
    if (-not $wantOn) {
        $stripped = Filter-Fixed $rows
        if ($stripped.Count -ne $rows.Count) {
            Write-Host "  SAFETY: fixed rows removed from toggle-off: $((@($rows | Where-Object { $fixedIdx.ContainsKey($_) })) -join ',')" -ForegroundColor Red
            Log "SAFETY: fixed rows removed from toggle-off: $((@($rows | Where-Object { $fixedIdx.ContainsKey($_) })) -join ',')"
            $rows = $stripped
            if (-not $rows.Count) { Write-Host "  nothing to toggle off (all fixed) - skipping"; return $true }
        }
    }
    $rows = @($rows | Where-Object { $_ -ne $null })
    for ($try = 1; $try -le 2; $try++) {
        $c = Connect-Snap
        if (-not $c) { Write-Host "  no snapshot (try $try)"; Start-Sleep -Seconds 3; continue }
        $chk = RowChecked $c.snap; $epoch = $c.snap.sepoch
        $need = @()
        foreach ($r in $rows) {
            if ($r -ne $null -and $chk) {
                if ($chk.ContainsKey($r)) {
                    $val = $chk[$r];
                    if ($wantOn) { if ($val -ne 1) { $need += $r } }
                    else { if ($val -eq 1) { $need += $r } }
                } else {
                    # Row missing in snapshot: treat as off for open, skip for close to avoid index crash
                    if ($wantOn) { $need += $r }
                }
            }
        }
        if (-not $need.Count) { $c.ws.Dispose(); Write-Host "  all rows already state (no-op)"; return $true }
        Write-Host "  epoch=$epoch toggling ($(if($wantOn){'ON'}else{'OFF'})): $($need -join ',')"
        foreach ($r in $need) { SW $c.ws ('{"t":"act","key":"root/1000#0","op":"row_toggle","r":' + $r + ',"id":"' + (Make-Id) + '","epoch":' + $epoch + '}'); Start-Sleep -Milliseconds 250 }
        Start-Sleep -Milliseconds 500
        $okAll = $true
        foreach ($raw in (DR $c.ws 6)) { try { $p = $raw | ConvertFrom-Json; if ($p.t -eq "act_result" -and -not $p.ok) { $okAll = $false; Write-Host "  act_result FAILED: $($p.id)" -ForegroundColor Red } } catch {} }
        $c.ws.Dispose()
        if ($okAll) { return $true }
        Write-Host "  some toggles failed, retrying (try $try)" -ForegroundColor Yellow; Start-Sleep -Seconds 5
    }
    return $false
}
function Kill-Local($clients) {
    $procs = Get-CimInstance Win32_Process -Filter "Name='qnyh.exe'" -ErrorAction SilentlyContinue
    foreach ($cid in $clients) {
        if (-not $cid) { continue }
        $cidRow = $clientToIdx[$cid]
        if ($null -eq $cidRow) { continue }
        if ($fixedIdx.ContainsKey($cidRow)) {
            Write-Host "  SAFETY: skip kill fixed client $cid" -ForegroundColor Red
            Log ("SAFETY: skip kill fixed client " + $cid)
            continue
        }
        $hit = @($procs | Where-Object { $_.CommandLine -match [regex]::Escape($cid) })
        foreach ($p in $hit) { Write-Host "    kill $cid PID=$($p.ProcessId)"; Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    }
    Start-Sleep -Seconds 5
}
function Wait-Boot($rows, [int]$secs, [string]$label) {
    $rows = @($rows | Where-Object { $_ -ne $null })
    # poll checked state + qnyh count until rows settle checked=1, or timeout
    $t0 = [DateTime]::UtcNow.AddSeconds($secs); $lastLen = -1
    while ([DateTime]::UtcNow -lt $t0) {
        Start-Sleep -Seconds 20
        $q = (Get-Process qnyh -ErrorAction SilentlyContinue | Measure-Object).Count
        $c = Connect-Snap
        if ($c) {
            $h = RowChecked $c.snap
            $on = @($rows | Where-Object { $h[$_] -eq 1 }).Count
            Write-Host "  [$label] poll qnyh=$q checked_on=$on/$($rows.Count) rows=$($rows -join ',')" -ForegroundColor DarkGray
            if ($on -eq $rows.Count -and $q -ge (10 - 2)) { $c.ws.Dispose(); return $true }
            $c.ws.Dispose()
        }
    }
    return $false
}
function Write-Desired($mapIdx) {
    # mapIdx: hashtable idx->'running'/'offline'; persists to DB (only DB writer besides SetDesired)
    $db = Get-Content "$dir\client_database.json" -Raw | ConvertFrom-Json
    foreach ($c in $db.clients) { if ($mapIdx.ContainsKey([int]$c.idx)) { $c.status = $mapIdx[[int]$c.idx] } }
    $db.lastUpdated = (Get-Date -Format "yyyy-MM-dd")
    $db | ConvertTo-Json -Depth 5 | Set-Content "$dir\client_database.json" -Encoding UTF8
}
function Execute-Slot($slot) {
    Write-Host "`n===== SLOT $($slot.time) $([DateTime]::Now.ToString('HH:mm:ss')) =====" -ForegroundColor Magenta
    Log "SLOT $($slot.time) start"
    $closeIdx = @(); $openIdx = @()
    foreach ($n in $slot.close) { $closeIdx += (Resolve-Idx $n) }
    $closeIdx = @($closeIdx | Where-Object { $_ -ne $null })
    $closeIdx = Filter-Fixed $closeIdx
    foreach ($n in $slot.open)  { $openIdx  += (Resolve-Idx $n) }
    $openIdx = @($openIdx | Where-Object { $_ -ne $null })
    $openIdx = Filter-Fixed $openIdx
    $closeClients = @($closeIdx | ForEach-Object { $i = $_; ($db.clients | Where-Object { [int]$_.idx -eq $i }).client })
    $openClients  = @($openIdx  | ForEach-Object { $i = $_; ($db.clients | Where-Object { [int]$_.idx -eq $i }).client })

    Write-Host "  CLOSE ($($closeIdx -join ','))  ->  OPEN ($($openIdx -join ','))"
    # 1: toggle off close group (checked=0) so app won't auto-restart
    $ok = Toggle-Rows $closeIdx $false
    if (-not $ok) { Write-Host "  ERROR: toggle-off close failed" -ForegroundColor Red; Log "SLOT $($slot.time) toggle-off FAILED"; return $false }
    # 2: kill local close-group processes
    Kill-Local $closeClients
    # 3: open group simultaneously on one connection
    $ok = Toggle-Rows $openIdx $true
    if (-not $ok) { Write-Host "  ERROR: open failed" -ForegroundColor Red; Log "SLOT $($slot.time) open FAILED"; return $false }
    # 4: wait for boot
    Wait-Boot $openIdx 180 "slot $($slot.time)"
    # 5: persist desired state
    $map = @{}
    foreach ($c in $db.clients) { $map[[int]$c.idx] = $c.status }  # keep untouched
    foreach ($i in $closeIdx) { $map[$i] = 'offline' }
    foreach ($i in $openIdx)  { $map[$i] = 'running' }
    Write-Desired $map
    Write-Host "  SLOT $($slot.time) done, desired persisted" -ForegroundColor Green
    Log "SLOT $($slot.time) DONE (close=$($closeIdx -join ',') open=$($openIdx -join ','))"
    return $true
}

# ---- state file ----
$statePath = "$dir\cache\cycle_state.json"
if (-not (Test-Path "$dir\cache")) { New-Item -ItemType Directory -Path "$dir\cache" | Out-Null }
$state = @{}
if (Test-Path $statePath) { try { $state = Get-Content $statePath -Raw | ConvertFrom-Json } catch {} }
$today = (Get-Date).ToString("yyyy-MM-dd")
if ($state.today -ne $today) { $state = @{ today = $today } }
if (-not $state.done) { $state.done = @{} }
# normalize done to a plain hashtable
$done = @{}
if ($state.done -is [System.Management.Automation.PSCustomObject]) { foreach ($p in $state.done.PSObject.Properties) { $done[$p.Name] = $p.Value } } else { $done = @{ } ; foreach ($k in $state.done.Keys) { $done[$k] = $state.done[$k] } }
$state.done = $done

$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"

$nowMode = ($args -contains "-Now")

# ---- slot driver: sorted boundaries + target resolution ----
$slots = @($cfg.schedule | Sort-Object { [int]([datetime]::ParseExact($_.time, 'HH:mm', $null).ToString('HHmm')) })
$n = $slots.Count
$slotMins = @()
foreach ($s in $slots) { $st = [datetime]::ParseExact($s.time, 'HH:mm', $null); $slotMins += ($st.Hour * 60) + $st.Minute }
function Get-CheckedMap {
    $c = Connect-Snap
    if (-not $c) { return $null }
    $h = RowChecked $c.snap
    $c.ws.Dispose()
    return $h
}
function Get-SlotOpenIdx($slot) {
    $out = @()
    foreach ($nm in $slot.open) { $out += (Resolve-Idx $nm) }
    return $out
}
function Resolve-Day($nowMin) {
    # Bring the correct group up for clock-time $nowMin without replaying history.
    # Active group = group opened by the most recent boundary <= nowMin (circular:
    # before the first boundary, the LAST slot's group owns the window).
    $targetIdx = -1
    for ($i = 0; $i -lt $n; $i++) { if ($nowMin -ge $slotMins[$i]) { $targetIdx = $i } }
    $wrap = $false
    if ($targetIdx -lt 0) { $targetIdx = $n - 1; $wrap = $true }

    # mark as skipped: passed boundaries strictly before the target (never re-run them)
    for ($i = 0; $i -lt $targetIdx; $i++) {
        if ($slotMins[$i] -ge $nowMin) { continue }
        $k = $slots[$i].time
        if (-not $state.done.ContainsKey($k)) {
            $state.done[$k] = 'skipped'
            Write-Host "  mark $k skipped (time already passed)" -ForegroundColor Yellow
            Log "mark $k skipped (time already passed)"
        }
    }

    $tar = $slots[$targetIdx]; $tk = $tar.time
    if ($wrap -and $state.done.ContainsKey($tk)) { $state.done.Remove($tk) }

    # skip work if the target group is already up
    $openIdx = @(Get-SlotOpenIdx $tar | Where-Object { $_ -ne $null })
    $h = Get-CheckedMap
    $active = $false
    if ($h) { $active = $true; foreach ($i in $openIdx) { if ($h[$i] -ne 1) { $active = $false; break } } }
    $q = (Get-Process qnyh -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($active -and $q -ge (5 + $openIdx.Count - 2)) {
        Write-Host "  target $tk group already active (checked + qnyh=$q) - no action" -ForegroundColor DarkGray
        Log ("resolve " + $tk + ": target already active, no action")
    }
    else {
        $ok = Execute-Slot $tar
        if ($ok -and -not $wrap) { $state.done[$tk] = (Get-Date -Format "HH:mm:ss") }
    }
    $state | ConvertTo-Json -Depth 5 | Set-Content $statePath -Encoding UTF8
}

Write-Host "auto-cycle running. today=$today slots: $(($slots.time -join ', '))" -ForegroundColor Cyan
Log "auto-cycle started vFIX2. mode=$(if($nowMode){'-Now'}else{'-Background'}) today=$today"
$didResolve = $false

while ($true) {
    try {
    $now = Get-Date
    $nowMin = ($now.Hour * 60) + $now.Minute

    # Liên tục theo thực tế — không reset 0h, không giới hạn lần mở
    # (Chỉ theo dõi trạng thái, không chặn thực thi)

    # Continuous resolve: always check target group every loop (unlimited opens / real-time)
    Resolve-Day $nowMin; $didResolve = $true

    # normal scheduler: run each undone slot exactly at/after its boundary
    foreach ($slot in $slots) {
        $key = $slot.time
        if ($state.done.ContainsKey($key)) { continue }  # already ran/skipped today
        $st = [datetime]::ParseExact($key, "HH:mm", $null)
        $slotMin = ($st.Hour * 60) + $st.Minute
        if ($nowMin -ge $slotMin) {
            $ok = Execute-Slot $slot
            if ($ok) { $state.done[$key] = (Get-Date -Format "HH:mm:ss") }
            $state | ConvertTo-Json -Depth 5 | Set-Content $statePath -Encoding UTF8
        }
    }

    # all slots done for today?
    $allDone = $true
    foreach ($slot in $slots) { if (-not $state.done.ContainsKey($slot.time)) { $allDone = $false; break } }
    if ($allDone -and $nowMin -ge (19*60 + 45)) {
        Write-Host "all slots done for today - exiting (or continue in -Background)" -ForegroundColor Green
        if ($args -contains "-Background") { Start-Sleep -Seconds 300; continue } else { break }
    }

    if ($nowMode) { break }
    Start-Sleep -Seconds 20
    } catch {
        Write-Host "loop error: $($_.Exception.Message)" -ForegroundColor Red
        Log ("loop error: " + $_.Exception.Message + " :: " + $_.ScriptStackTrace)
        Start-Sleep -Seconds 30
    }
}