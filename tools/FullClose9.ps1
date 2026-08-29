#FullClose9.ps1 - REAL close of row 9: list_menu -> menu -> T?t gi? l?p -> confirm Có -> verify
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 1048576
$TARGET = 9

function New-WS {
    $w = New-Object System.Net.WebSockets.ClientWebSocket
    $w.Options.SetRequestHeader("Authorization", "Bearer $token")
    $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $w.ConnectAsync($uri, $ct).Wait(); $w
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    $out = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) {
    Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
    Send-WS $ws '{"t":"launch","product_id":73}'
}
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }

# Collect scan of snapshot: rows + any popup/dialog nodes
function Scan($snap, [string]$label) {
    Write-Host "`n--- SCAN: $label ---" -ForegroundColor Magenta
    foreach ($n in $snap.b.children) {
        $txt = ($n.text -replace '[^\x20-\x7E]','')
        Write-Host "  node key=$($n.key) kind=$($n.kind) title='$txt'" -ForegroundColor DarkGray
        if ($n.key -eq "root/1000#0") {
            foreach ($row in $n.rows) { Write-Host "       row $($row.r) chk=$($row.checked)" -ForegroundColor $(if($row.checked -eq 1){"Green"}else{"Gray"}) }
        }
        if ($n.key -match 'popup') {
            Write-Host "    POPUP FOUND: key=$($n.key) kind=$($n.kind)" -ForegroundColor Cyan
            if ($n.children) { foreach ($c in $n.children) { Write-Host "       item key=$($c.key) text='$(($c.text -replace '[^\x20-\x7E]',''))' kind=$($c.kind)" -ForegroundColor Yellow } }
        }
        if ($n.children) {
            foreach ($c in $n.children) {
                $ctxt = ($c.text -replace '[^\x20-\x7E]','')
                if ($c.key -match 'popup' -or $c.kind -in @('menupopup','dialog','contextmenu')) { Write-Host "     sub node key=$($c.key) kind=$($c.kind) text='$ctxt'" -ForegroundColor Cyan }
            }
        }
    }
}

Write-Host "### STEP 0: connection + snapshot ###" -ForegroundColor Magenta
$ws = New-WS
Write-Host "Connected: $($ws.State)"
Open-UI $ws
$epoch = 0
$rows = @{}
foreach ($raw in (Drain $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Scan $p "initial" }
    elseif ($p.t -eq "scr_list_res") {
        Write-Host "`n--- scr_list_res ---" -ForegroundColor Magenta
        Write-Host "  instances=$($p.instances.Count) seatsUsed=$($p.seatsUsed) seatsMax=$($p.seatsMax) quotaLeft=$($p.quotaLeft)"
        foreach ($inst in $p.instances) { Write-Host "  inst: $($inst | ConvertTo-Json -Compress -Depth 4)" -ForegroundColor DarkGray }
    }
}
Write-Host "epoch=$epoch state before act: $($ws.State)" -ForegroundColor Cyan

Write-Host "`n### STEP 1: list_menu r=$TARGET ###" -ForegroundColor Magenta
Send-WS $ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $TARGET + '}')
Start-Sleep -Milliseconds 600
$popup = @()
foreach ($raw in (Drain $ws 4)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $popup += ($raw | ConvertFrom-Json) }
    elseif ($p.t -eq "delta") { Write-Host "  delta" -ForegroundColor DarkGray; if ($p.b) { $popup += ($p | ConvertFrom-Json) } }
    elseif ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
    else { Write-Host "  $($p.t)" -ForegroundColor DarkGray }
}
Write-Host "list_menu done, state=$($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
$ws.Dispose()

# ===== if connection aborted, reconnect to inspect the open menu state =====
if ($popup.Count -eq 0) {
    Write-Host "`nConnection dropped / no popup yet. Reconnecting to inspect state..." -ForegroundColor Yellow
    Start-Sleep -Seconds 1
    $ws = New-WS; Open-UI $ws
    foreach ($raw in (Drain $ws 6)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { Scan $p "after-list-menu(reconnect)"; $epoch = $p.sepoch }
    }
    $ws.Dispose()
}