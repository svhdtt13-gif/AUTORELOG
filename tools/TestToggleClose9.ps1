#TestToggleClose9.ps1 - row_toggle r=9 directly, verify, then reopen
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
function Get-Snapshot($ws) {
    Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
    Send-WS $ws '{"t":"launch","product_id":73}'
    $timeout = [DateTime]::UtcNow.AddSeconds(8)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "snapshot") { $ms.Dispose(); return $p }
            } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $null
}
function Row-Chk($snap, $r) { foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { return ($n.rows | Where-Object { $_.r -eq $r }).checked } }; return $null }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }

Write-Host "### before ###" -ForegroundColor Magenta
$ws = New-WS; $snap = Get-Snapshot $ws
Write-Host "row9=$([char]34)chk=$(Row-Chk $snap 9)$([char]34) epoch=$($snap.sepoch)" -ForegroundColor Cyan
$ws.Dispose()

Write-Host "### row_toggle r=9 ###" -ForegroundColor Magenta
$ws = New-WS; $snap = Get-Snapshot $ws
$epoch = $snap.sepoch
$id = Make-Id
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":9,"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "SEND: $msg" -ForegroundColor Yellow
Send-WS $ws $msg
# capture any reply for 5s
$timeout = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(600)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
            elseif ($p.t -eq "snapshot") { Write-Host "  snapshot gen=$($p.gen)" -ForegroundColor Gray }
            else { Write-Host "  $($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
Write-Host "state=$($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
$ws.Dispose()

Write-Host "### after (wait 6s) ###" -ForegroundColor Magenta
Start-Sleep -Seconds 6
$ws = New-WS; $snap = Get-Snapshot $ws
Write-Host "row9 chk=$(Row-Chk $snap 9)  $(if ((Row-Chk $snap 9) -eq 0) {'[CLOSED!]'} elseif ((Row-Chk $snap 9) -eq 1) {'[STILL RUN]'} else {'[unknown]'})" -ForegroundColor Cyan
$ws.Dispose()