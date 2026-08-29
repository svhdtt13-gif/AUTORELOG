#ToggleOffVerify.ps1 - row_toggle OFF row 9, then check scr_list_res instance state
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
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Show-Inst($p) {
    if ($p.t -eq "scr_list_res") {
        Write-Host "  scr_list_res: instances=$($p.instances.Count) seatsUsed=$($p.seatsUsed) seatsMax=$($p.seatsMax)" -ForegroundColor Cyan
        $i9 = $p.instances | Where-Object { $_.idx -eq 9 }
        $i0 = $p.instances | Where-Object { $_.idx -eq 0 }
        Write-Host "    idx 0 (client_14): state=$($i0.state) cap=$($i0.cap)" -ForegroundColor $(if($i0.state -eq 'running'){"Green"}else{"Gray"})
        Write-Host "    idx 9 (khoqua09): state=$($i9.state) cap=$($i9.cap)" -ForegroundColor $(if($i9.state -eq 'running'){"Green"}else{"Gray"})
    }
}

$ws = New-WS; Open-UI $ws
Write-Host "=== BEFORE toggle (drain) ===" -ForegroundColor Magenta
$epoch = 0
foreach ($raw in (Drain $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $epoch = $p.sepoch; foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { Write-Host "  row9 chk=$(($n.rows | Where-Object {$_.r -eq 9}).checked)" -ForegroundColor Cyan } } }
    if ($p.t -eq "scr_list_res") { Show-Inst $p }
}
Write-Host "epoch=$epoch" -ForegroundColor DarkGray

Write-Host "`n=== TOGGLE OFF row 9 ===   aim: close emulator WINDOW completely" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":9,"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "SEND: $msg"
Send-WS $ws $msg
foreach ($raw in (Drain $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
    if ($p.t -eq "scr_list_res") { Show-Inst $p }
}
Write-Host "state=$($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
$ws.Dispose()

Start-Sleep -Seconds 6
Write-Host "`n=== AFTER (fresh conn, 6s later) ===" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
foreach ($raw in (Drain $ws 8)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { Write-Host "  row9 chk=$(($n.rows | Where-Object {$_.r -eq 9}).checked)" -ForegroundColor $(if((($n.rows | Where-Object {$_.r -eq 9}).checked) -eq 1){"Green"}else{"Red"}) } } }
    if ($p.t -eq "scr_list_res") { Show-Inst $p }
}
$ws.Dispose()