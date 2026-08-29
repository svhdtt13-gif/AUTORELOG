#ScheduleCycle.ps1 - DRY-RUN simulation of the full schedule cycle from config.json
#Does NOT touch emulators. Reads live state once, then simulates each slot.
param()
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$cfg = Get-Content "$dir\config.json" -Raw | ConvertFrom-Json
$db  = Get-Content "$dir\client_database.json" -Raw | ConvertFrom-Json

# mapping name (config-normalized) -> client id (from config.emulators.scheduled)
$nameToClient = @{}
foreach ($e in $cfg.emulators.scheduled) { $nameToClient[$e.name] = $e.client }
foreach ($e in $cfg.emulators.fixed)     { $nameToClient[$e.name] = $e.client }
# alias fixes (config uses ASCII names that differ from DB unicode or roster)
$alias = @{
  "HANMI"  = "client_41"; "Ahihi10" = "client_42"; "Ahihi6" = "client_43"; "Ahihi8" = "client_44"; "Ahihi9" = "client_45"
  "MachNhi"= "client_46"; "DoanVanThu" = "client_47"; "LieuAnh" = "client_48"; "BinhDuc" = "client_49"; "DieuLinh" = "client_50"
  "khoqua08" = "client_2"; "khoqua07" = "client_5"; "Me" = "client_6"; "khoqua09" = "client_7"; "khoqua10" = "client_8"
  "NA" = "client_31"; "COC" = "client_32"; "XOAI" = "client_33"; "CHUOI" = "client_34"; "CAM" = "client_35"
}
foreach ($k in $alias.Keys) { $nameToClient[$k] = $alias[$k] }

# client -> idx from DB
$clientToIdx = @{}
foreach ($c in $db.clients) { $clientToIdx[$c.client] = [int]$c.idx }
$clientName = @{}
foreach ($c in $db.clients) { $clientName[$c.client] = $c.name }
$clientGroup = @{}
foreach ($c in $db.clients) { $clientGroup[$c.client] = $c.group }

function Resolve-Client($name) {
    if ($nameToClient.ContainsKey($name)) { return $nameToClient[$name] }
    return $name  # assume it's already a client id
}

# ---- live running state ----
$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None; $buf = New-Object byte[] 2097152
$w = New-Object System.Net.WebSockets.ClientWebSocket
$w.Options.SetRequestHeader("Authorization", "Bearer $token")
$w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$w.ConnectAsync($uri, $ct).Wait()
function SW($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $w.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function DR([int]$secs) { $t=[DateTime]::UtcNow.AddSeconds($secs); $o=@(); while([DateTime]::UtcNow -lt $t -and $w.State -eq "Open"){ try{ $ms=New-Object System.IO.MemoryStream; $more=$true; while($more -and $w.State -eq "Open"){ $r=$w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)),$ct); if($r.AsyncWaitHandle.WaitOne(400)){ $ms.Write($buf,0,$r.Result.Count); $more=-not $r.Result.EndOfMessage } else { $more=$false } }; if($ms.Length -gt 0){ $o += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }; $ms.Dispose() } catch { break } }; return $o }
SW '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
SW '{"t":"launch","product_id":73}'
$gotSnap = $false; $snap = $null
# snapshot: break early on first snapshot (draining full 8s closes the socket)
$snap = $null
$tS = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $tS -and $w.State -eq "Open" -and -not $snap) {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $w.State -eq "Open") {
            $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snap = $p }
        }
        $ms.Dispose()
    } catch { break }
}
$gotSnap = ($null -ne $snap)
if (-not $gotSnap) { Write-Host "ERROR: no snapshot" -ForegroundColor Red; exit 1 }
Start-Sleep -Milliseconds 500
SW '{"t":"scr_list"}'
$liveRunning = @{}   # client -> bool
$attempted = 0
$seenTypes = @{}
$t1 = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $t1 -and $w.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $w.State -eq "Open") {
            $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if (-not $seenTypes.ContainsKey([string]$p.t)) { $seenTypes[[string]$p.t] = 1 }
            if ($p.t -eq "scr_list_res") { foreach ($i in $p.instances) { $idx = [int]$i.idx; $cl = $db.clients | Where-Object { [int]$_.idx -eq $idx } | Select-Object -First 1; if ($cl) { $liveRunning[$cl.client] = ($i.state -eq 'running') } }; $attempted++ }
        }
        $ms.Dispose()
    } catch { break }
}
Write-Host "  [live] message types seen: $(($seenTypes.Keys) -join ', ')" -ForegroundColor DarkGray
$w.Dispose()

# rows' checked state (auto ON) from snapshot
$rowChecked = @{}
foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { foreach ($r in $n.rows) { $cl = $db.clients | Where-Object { [int]$_.idx -eq [int]$r.r } | Select-Object -First 1; if ($cl) { $rowChecked[$cl.client] = [int]$r.checked } } } }

Write-Host "=== LIVE (dry-run basis) ===" -ForegroundColor Cyan
foreach ($c in ($db.clients | Sort-Object idx)) {
    $st = if ($liveRunning.ContainsKey($c.client) -and $liveRunning[$c.client]) { "running" } else { "off" }
    $chk = if ($rowChecked.ContainsKey($c.client)) { "chk=$($rowChecked[$c.client])" } else { "chk=?" }
    Write-Host ("  {0,2} {1,-10} {2,-8} {3} {4}" -f $c.idx, $c.client, $st, $chk, $c.name)
}

# ---- simulate cycle ----
$state = @{}   # client -> $true running
foreach ($cl in $db.clients) { $state[$cl.client] = ($liveRunning.ContainsKey($cl.client) -and $liveRunning[$cl.client]) }

Write-Host "`n=== FULL CYCLE SIMULATION (no emulator touched) ===" -ForegroundColor Magenta
$fixedList = @($cfg.emulators.fixed | ForEach-Object { $_.client })
$unusual = @()

foreach ($slot in $cfg.schedule) {
    Write-Host "`n--- Slot $($slot.time) ---" -ForegroundColor Yellow
    $toClose = @(); $toOpen = @(); $noopC = @(); $noopO = @()
    foreach ($n in $slot.close) { $c = Resolve-Client $n; if ($state[$c]) { $toClose += $c } else { $noopC += $c } }
    foreach ($n in $slot.open) { $c = Resolve-Client $n; if ($state[$c]) { $noopO += $c } else { $toOpen += $c } }
    if ($toClose) { foreach ($c in $toClose) { Write-Host "  CLOSE $c ($($clientName[$c])) [idx $($clientToIdx[$c])]" -ForegroundColor Red; $state[$c] = $false } }
    if ($noopC) { foreach ($c in $noopC) { Write-Host "  close(already off): $c" -ForegroundColor DarkGray } }
    if ($toOpen) { foreach ($c in $toOpen) { Write-Host "  OPEN  $c ($($clientName[$c])) [idx $($clientToIdx[$c])]" -ForegroundColor Green; $state[$c] = $true } }
    if ($noopO) { foreach ($c in $noopO) { Write-Host "  open(already on): $c" -ForegroundColor DarkGray } }
    # check ordering hazard: full close required before open per user rule
    if ($toClose.Count -gt 0 -and $toOpen.Count -gt 0) {
        Write-Host "  -> order: CLOSE first, then OPEN (user rule 'phai tat hoan toan truoc khi mo')" -ForegroundColor DarkGray
    }
    foreach ($c in $toOpen) { if ($fixedList -contains $c) { $unusual += "SLOT $($slot.time): tried to OPEN fixed $c" } }
}

Write-Host "`n=== END STATE after full cycle ===" -ForegroundColor Magenta
foreach ($cl in @($db.clients | Sort-Object idx)) {
    $st = if ($state[$cl.client]) { "running" } else { "off" }
    $color = if ($state[$cl.client]) { "Green" } else { "DarkGray" }
    Write-Host ("  {0,2} {1,-10} {2,-8} {3}" -f $cl.idx, $cl.client, $st, $cl.name) -ForegroundColor $color
}
$cnt = @($db.clients | Where-Object { $state[$_.client] }).Count
Write-Host "`nTotal running at end of cycle: $cnt" -ForegroundColor Cyan

# sanity checks
Write-Host "`n=== CONSISTENCY CHECKS ===" -ForegroundColor Magenta
$fixedDown = @($db.clients | Where-Object { $_.group -eq "fixed" -and -not $state[$_.client] })
if ($fixedDown.Count) { Write-Host "  [WARN] fixed would end OFF (script never toggles fixed, so this means they were down at live start): $($fixedDown.client -join ', ')" -ForegroundColor Yellow }
else { Write-Host "  fixed all ON through cycle" -ForegroundColor Green }
$neverSeen = @($db.clients | Where-Object { $_.group -eq "scheduled" -and -not $liveRunning.ContainsKey($_.client) -and -not $liveRunning[$_.client] })
# clients that appear in schedule but have never been seen running AND are not the current 6/9 pair
$schedClients = @{}
foreach ($slot in $cfg.schedule) { foreach ($n in $slot.open) { $schedClients[(Resolve-Client $n)] = $true } }
Write-Host "  Clients referenced by schedule: $(($schedClients.Keys | Sort-Object) -join ', ')"
$unproven = @($schedClients.Keys | Where-Object { -not $liveRunning[$_] -and $_ -notin @('client_45','client_46') })
if ($unproven.Count) { Write-Host "  [INFO] schedule clients never seen running (not yet proven to boot): $($unproven -join ', ')" -ForegroundColor Yellow }
if ($unusual.Count) { Write-Host "  [WARN]" ; $unusual | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow } }