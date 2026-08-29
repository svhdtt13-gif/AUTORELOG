#CloseTogether.ps1 - set several rows OFF simultaneously on ONE WebSocket connection (row_toggle only if checked=1)
# Usage: $env:AGROWS='10,11,12,13,14'; powershell -File CloseTogether.ps1
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
$rows = @((($env:AGROWS) -split '[\s,]+') | Where-Object { $_ } | ForEach-Object { [int]$_.Trim() })

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
function Connect-Snap {
    $w = New-WS; Open-UI $w
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
    foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { foreach ($rw in $n.rows) { $h[[int]$rw.r] = $rw.checked } } }
    return $h
}

$c = Connect-Snap
if (-not $c) { Write-Host "no snapshot"; exit 1 }
$chk = RowChecked $c.snap
$epoch = $c.snap.sepoch
Write-Host "epoch=$epoch"
foreach ($r in $rows) {
    if ($chk[[int]$r] -eq 1) {
        $id = Make-Id
        $msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":' + $r + ',"id":"' + $id + '","epoch":' + $epoch + '}'
        Send-WS $c.ws $msg
        Write-Host "SENT toggle-off r=$r"
        Start-Sleep -Milliseconds 250
    } else {
        Write-Host "row $r already checked=0 (skip)"
    }
}
Start-Sleep -Milliseconds 500
foreach ($raw in (Drain $c.ws 6)) {
    try { $p = $raw | ConvertFrom-Json; if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }; if ($p.t -eq "snapshot") { $h = RowChecked $p; foreach ($r in $rows) { Write-Host "  after-snap row $r checked=$($h[[int]$r])" } } } catch {}
}
$c.ws.Dispose()