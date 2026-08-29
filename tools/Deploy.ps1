#Deploy.ps1 - batch deploy: set desired running state per client, diff vs live, open/close emulators
# Usage: powershell -File Deploy.ps1 [-Database <path>] [-DryRun] [-Only <idx1,idx2>]
param(
    [string]$Database = "C:\Users\ADMIN\Documents\ai tool\tools\client_database.json",
    [switch]$DryRun,
    [string]$Only = ""
)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152

function New-WS { $w = New-Object System.Net.WebSockets.ClientWebSocket; $w.Options.SetRequestHeader("Authorization", "Bearer $token"); $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20); $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token"); $w.ConnectAsync($uri, $ct).Wait(); $w }
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs); $out = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(400)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Get-Snapshot($ws, [int]$secs) {
    foreach ($raw in (Drain $ws $secs)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
    return $null
}
function Connect-and-Snap { $w = New-WS; Open-UI $w; $s = Get-Snapshot $w 6; return @{ ws = $w; snap = $s } }
function Scan-Popup($node) {
    $r = $null
    if ($node.popup -eq $true -and $node.kind -eq "menu") { $r = $node }
    if (-not $r -and $node.children) { foreach ($c in $node.children) { $r = Scan-Popup $c; if ($r) { break } } }
    return $r
}

# --- get live running state ---
function Get-LiveRunning {
    $w = New-WS; Open-UI $w
    $live = @{}
    # wait for snapshot first
    $gotSnap = $false
    $t0 = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $t0 -and $w.State -eq "Open" -and -not $gotSnap) {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $w.State -eq "Open") {
                $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
            }
            if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { $gotSnap = $true } }
            $ms.Dispose()
        } catch { break }
    }
    if ($gotSnap) {
        Send-WS $w '{"t":"scr_list"}'
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
                    if ($p.t -eq "scr_list_res") { foreach ($i in $p.instances) { $live[[int]$i.idx] = ($i.state -eq 'running') } }
                }
                $ms.Dispose()
            } catch { break }
        }
    }
    $w.Dispose()
    return $live
}

# --- open one row via row_toggle (proven); idempotent: toggle only if currently OFF ---
function Open-One($idx) {
    $c = Connect-and-Snap
    if (-not $c.snap) { return $false }
    # check current checked state
    $cur = $null
    foreach ($n in $c.snap.b.children) { if ($n.key -eq "root/1000#0") { $row = $n.rows | Where-Object { $_.r -eq $idx }; if ($row) { $cur = $row.checked } } }
    if ($cur -ne 1) {
        $id = Make-Id
        $msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":' + $idx + ',"id":"' + $id + '","epoch":' + $c.snap.sepoch + '}'
        Send-WS $c.ws $msg
        Start-Sleep -Milliseconds 600
    } else {
        Write-Host "  row $idx already ON (checked=1) - skip toggle" -ForegroundColor DarkGray
    }
    $c.ws.Dispose()
    Start-Sleep -Seconds 3
    return $true
}

# --- close one row (proven full-close) ---
function Close-One($idx) {
    $ok = $false
    # step 1: open menu
    $c1 = Connect-and-Snap
    if (-not $c1.snap) { return $false }
    Send-WS $c1.ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $idx + '}')
    Start-Sleep -Milliseconds 300
    $c1.ws.Dispose()
    $popupKey = $null; $itemPos = $null; $snapTmp = $null
    for ($try = 1; $try -le 5 -and -not $popupKey; $try++) {
        Start-Sleep -Milliseconds 400
        $c = Connect-and-Snap
        if ($c.snap) { $snapTmp = $c.snap; $pc = Scan-Popup $c.snap.b; if ($pc) { $popupKey = $pc.key; $it2 = $pc.items | Where-Object { $_.cmd -eq 32773 }; if ($it2) { $itemPos = $it2.pos } } }
        $c.ws.Dispose()
    }
    if (-not $popupKey -or $null -eq $itemPos) { return $false }
    $c3 = Connect-and-Snap
    if ($c3.snap) {
        $id = Make-Id
        $msg = '{"t":"act","key":"' + $popupKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $snapTmp.sepoch + '}'
        Send-WS $c3.ws $msg; Start-Sleep -Milliseconds 600
    }
    $c3.ws.Dispose()
    $coKey = $null; $msgSnap = $null
    for ($try = 1; $try -le 5 -and -not $coKey; $try++) {
        Start-Sleep -Milliseconds 400
        $c = Connect-and-Snap
        if ($c.snap) {
            $msgSnap = $c.snap
            foreach ($n in $c.snap.b.children) {
                if ($n.popup -eq $true -and $n.kind -eq "msgbox") {
                    if ($n.children) { foreach ($ch in $n.children) { if ($ch.kind -eq "button" -and $ch.id -eq 6) { $coKey = $ch.key } } }
                    if (-not $coKey) { foreach ($ch in $n.children) { if ($ch.kind -eq "button") { $coKey = $ch.key; break } } }
                }
            }
        }
        $c.ws.Dispose()
    }
    if (-not $coKey) { return $false }
    $c5 = Connect-and-Snap
    if ($c5.snap) {
        $id = Make-Id
        $msg = '{"t":"act","key":"' + $coKey + '","op":"toggle","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
        Send-WS $c5.ws $msg; Start-Sleep -Milliseconds 800
    }
    $c5.ws.Dispose()
    return $true
}

# --- main ---
$db = Get-Content $Database -Raw | ConvertFrom-Json
$live = Get-LiveRunning
Write-Host "=== LIVE running ===" -ForegroundColor Cyan
foreach ($c in $db.clients) { $r = if ($live.ContainsKey([int]$c.idx) -and $live[[int]$c.idx]) { 'running' } else { 'off' }; Write-Host ("  {0,2} {1,-10} {2,-8} {3}" -f $c.idx, $c.client, $r, $c.name) -ForegroundColor $(if($r -eq 'running'){"Green"}else{"DarkGray"}) }

$onlyIdx = @()
if ($Only) { $onlyIdx = ($Only -split ',' | ForEach-Object { [int]$_.Trim() }) }

$log = @()
foreach ($c in ($db.clients | Sort-Object idx)) {
    if ($onlyIdx.Count -and $onlyIdx -notcontains [int]$c.idx) { continue }
    if ($c.group -eq "fixed") { Write-Host "  row $($c.idx) ($($c.client)) FIXED - skip" -ForegroundColor DarkGray; continue }
    $desired = ($c.status -eq "running")
    $isLive = ($live.ContainsKey([int]$c.idx) -and $live[[int]$c.idx])
    if ($desired -eq $isLive) { Write-Host "  row $($c.idx) ($($c.client)) already $(if($desired){'running'}else{'off'}) - noop" -ForegroundColor Gray; $log += "$($c.client):noop"; continue }
    if ($Desired) {
        if ($DryRun) { Write-Host "  [DRY] would OPEN row $($c.idx) ($($c.client))" -ForegroundColor Yellow; $log += "$($c.client):dry-open" }
        else { $ok = Open-One [int]$c.idx; Write-Host "  OPEN row $($c.idx) ($($c.client)) -> $ok" -ForegroundColor $(if($ok){"Green"}else{"Red"}); $log += "$($c.client):open:$ok" }
    } else {
        if ($DryRun) { Write-Host "  [DRY] would CLOSE row $($c.idx) ($($c.client))" -ForegroundColor Yellow; $log += "$($c.client):dry-close" }
        else { $ok = Close-One [int]$c.idx; Write-Host "  CLOSE row $($c.idx) ($($c.client)) -> $ok" -ForegroundColor $(if($ok){"Green"}else{"Red"}); $log += "$($c.client):close:$ok" }
        Start-Sleep -Seconds 2
    }
}
Write-Host "`n=== DEPLOY SUMMARY ===" -ForegroundColor Magenta
$log | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
Write-Host "(note: database desired-state is NOT auto-updated; run SetDesired.ps1 to change desired state)" -ForegroundColor DarkGray