#DualConn.ps1 - Keep portal WS open + control WS, then row_toggle
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$portalRoom = "9b2ec1b5372e3ade"
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None

# === PORTAL CONNECTION ===
$portal = New-Object System.Net.WebSockets.ClientWebSocket
$portal.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token&disp=web")
$portal.ConnectAsync($uri, $ct).Wait()
Write-Host "Portal: $($portal.State)" -ForegroundColor Green
$portalBuf = New-Object byte[] 1048576
function Send-Portal($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $portal.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
Send-Portal '{"t":"_hello"}'
Start-Sleep -Milliseconds 800
# Drain portal non-blocking
$drain = { param($ws, $secs)
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$script:portalBuf)), ([System.Threading.CancellationToken]::None))
                if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($portalBuf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
}
& $drain $portal 1

# === CONTROL CONNECTION ===
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri2 = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ws.ConnectAsync($uri2, $ct).Wait()
Write-Host "Control: $($ws.State)" -ForegroundColor Green
$buf = New-Object byte[] 1048576
function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500

# Read snapshot / epoch
$epoch = 0
$timeout = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Write-Host "Control snapshot sepoch=$epoch" -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
Write-Host "Portal state during control read: $($portal.State)" -ForegroundColor Cyan

# Now row_toggle
$chars = "abcdefghijklmnopqrstuvwxyz0123456789"
$Ah = ""; for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
$msg = @{ t="act"; key="root/1000#0"; op="row_toggle"; r=0; id="$Ah`:1"; epoch=$epoch; holds=@(@{key="root/1000#0"; field="row:0:checked"}) } | ConvertTo-Json -Compress
Write-Host "`nrow_toggle: $msg" -ForegroundColor Yellow
Send- $msg

$timeout2 = [DateTime]::UtcNow.AddSeconds(6)
$got = $false
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") { Write-Host "ACT_RESULT ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }); $got = $true }
            elseif ($p.t -eq "snapshot") { Write-Host "snapshot gen=$($p.gen)" -ForegroundColor Green; $got = $true }
            else { Write-Host "$($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
Write-Host "Control final: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })

$portal.Dispose()
$ws.Dispose()