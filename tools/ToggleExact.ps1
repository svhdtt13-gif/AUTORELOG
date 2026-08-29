#ToggleExact.ps1 - row_toggle EXACT browser wire format, no holds
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$epoch = 0
$timeout = [DateTime]::UtcNow.AddSeconds(6)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Write-Host "snapshot sepoch=$epoch" -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

$chars = "abcdefghijklmnopqrstuvwxyz0123456789"
$Ah = ""; for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
$id = "$Ah`:1"
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":0,"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "`nSEND: $msg" -ForegroundColor Yellow
Send- $msg

$timeout2 = [DateTime]::UtcNow.AddSeconds(8)
$t0 = [DateTime]::UtcNow
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") {
                Write-Host "ACT_RESULT ok=$($p.ok) reason=$($p.reason) id=$($p.id)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
                if ($p.holds) { Write-Host "  holds: $($p.holds | ConvertTo-Json -Compress)" -ForegroundColor Cyan }
            }
            elseif ($p.t -eq "snapshot") { Write-Host "SNAPSHOT gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor Green }
            elseif ($p.t -eq "_blocked") { Write-Host "_blocked" -ForegroundColor Red }
            else { Write-Host "$($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
$el = ([DateTime]::UtcNow - $t0).TotalSeconds
Write-Host "`nFinal state: $($ws.State) after $([math]::Round($el,1))s" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })

# If still open, re-read snapshot to see row 0 checked state
if ($ws.State -eq "Open") {
    Write-Host "`n=== Re-reading list state ===" -ForegroundColor Green
    Send- '{"t":"resync"}'
    $timeout3 = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout3 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "snapshot") {
                    foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { foreach ($row in $n.rows) { if ($row.r -le 2) { Write-Host "  row $($row.r) checked=$($row.checked)" -ForegroundColor Cyan } } } }
                    break
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
}
$ws.Dispose()