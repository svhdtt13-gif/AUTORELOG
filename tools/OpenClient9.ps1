#OpenClient9.ps1 - reopen khoqua09 (row 9): row_toggle with fresh epoch, verify
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
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

$c = New-WS; Open-UI $c
$snap = Get-Snapshot $c 8
if (-not $snap) { Write-Host "no snapshot"; exit }
$epoch = $snap.sepoch
Write-Host "epoch=$epoch state=$($c.State)"

# check row 9 chk + name/state
foreach ($n in $snap.b.children) {
    if ($n.key -eq "root/1000#0") {
        $row = $n.rows | Where-Object { $_.r -eq $TARGET }
        if ($row) { Write-Host "row ${TARGET}: chk=$($row.chk) checked=$($row.checked)" -ForegroundColor Cyan }
    }
}

$id = Make-Id
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":' + $TARGET + ',"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "SEND: $msg" -ForegroundColor Yellow
Send-WS $c $msg
Start-Sleep -Milliseconds 800
foreach ($raw in (Drain $c 4)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
Write-Host "  state after row_toggle: $($c.State)" -ForegroundColor $(if($c.State -eq "Open"){"Green"}else{"Red"})
$c.Dispose()

Write-Host "`n### VERIFY (wait 25s for emulator boot) ###" -ForegroundColor Magenta
Start-Sleep -Seconds 25

$c2 = New-WS; Open-UI $c2
$snap2 = Get-Snapshot $c2 8
if ($snap2) {
    foreach ($n in $snap2.b.children) { if ($n.key -eq "root/1000#0") { $row = $n.rows | Where-Object { $_.r -eq $TARGET }; if ($row) { Write-Host "row ${TARGET}: chk=$($row.chk) checked=$($row.checked)" -ForegroundColor Cyan } } }
}
Start-Sleep -Milliseconds 300
Send-WS $c2 '{"t":"scr_list"}'
for ($n = 0; $n -lt 3 -and $c2.State -eq "Open"; $n++) {
    foreach ($raw in (Drain $c2 6)) {
        if ($c2.State -ne "Open") { break }
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "scr_list_res") {
            $i = $p.instances | Where-Object { $_.idx -eq $TARGET }
            if ($i) { Write-Host "idx$TARGET ($($i.id)) state=$($i.state)  $(if($i.state -eq 'running'){'RUNNING'}else{'NOT RUNNING'})" -ForegroundColor $(if($i.state -eq 'running'){"Green"}else{"Red"}) }
            $run = @($p.instances | Where-Object { $_.state -eq 'running' })
            Write-Host "total running: $($run.Count)/27" -ForegroundColor Gray
        }
    }
}
$c2.Dispose()
Write-Host "--- local qnyh (khoqua09) ---"
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'khoqua09|client_7' } | ForEach-Object { Write-Host "  PID=$($_.Id) $($_.MainWindowTitle)" -ForegroundColor Green }
Write-Host "total qnyh: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Gray