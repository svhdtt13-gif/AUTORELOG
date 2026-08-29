#FastPopup.ps1 - send list_menu r=9, reconnect FAST to catch transient popup
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 1048576

function New-WS {
    $w = New-Object System.Net.WebSockets.ClientWebSocket
    $w.Options.SetRequestHeader("Authorization", "Bearer $token")
    $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $w.ConnectAsync($uri, $ct).Wait(); $w
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs); $out = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Scan-Popup($snap) {
    $found = @()
    foreach ($n in $snap.b.children) {
        if ($n.key -match 'popup' -or $n.kind -in @('menu','menupopup','contextmenu')) {
            $found += "top: $($n.key) kind=$($n.kind) text=$(($n.text -replace '[^\x20-\x7E]',''))"
            if ($n.children) { foreach ($c in $n.children) { $found += "   item $($c.key) kind=$($c.kind) text=$(($c.text -replace '[^\x20-\x7E]',''))" } }
        }
        if ($n.children) { foreach ($c in $n.children) {
            if ($c.key -match 'popup' -or $c.kind -in @('menu','menupopup','contextmenu')) {
                $found += "sub: $($c.key) kind=$($c.kind) text=$(($c.text -replace '[^\x20-\x7E]',''))"
                if ($c.children) { foreach ($cc in $c.children) { $found += "     item $($cc.key) kind=$($cc.kind) text=$(($cc.text -replace '[^\x20-\x7E]',''))" } }
            }
        } }
    }
    return $found
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
    Write-Host "`n===== ATTEMPT $attempt : list_menu r=9 =====" -ForegroundColor Magenta
    $ws = New-WS; Open-UI $ws
    $epoch = 0
    foreach ($raw in (Drain $ws 4)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { $epoch = $p.sepoch }
    }
    Write-Host "epoch=$epoch - sending list_menu..." -ForegroundColor Yellow
    Send-WS $ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":9}')
    Start-Sleep -Milliseconds 220
    foreach ($raw in (Drain $ws 2)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot" -or $p.t -eq "delta") {
            $pp = Scan-Popup $p
            if ($pp) { foreach ($x in $pp) { Write-Host "  POPUP> $x" -ForegroundColor Green } }
        }
    }
    Write-Host "after list_menu state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
    $ws.Dispose()

    # FAST reconnect
    Start-Sleep -Milliseconds 200
    $ws = New-WS; Open-UI $ws
    Write-Host "reconnected fast, scanning for popup..." -ForegroundColor Yellow
    $hits = @()
    foreach ($raw in (Drain $ws 3)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") {
            $pp = Scan-Popup $p
            if ($pp) { foreach ($x in $pp) { Write-Host "  POPUP> $x" -ForegroundColor Green } }
        }
    }
    $ws.Dispose()
    Write-Host "attempt done" -ForegroundColor DarkGray
}