#TestStopKey.ps1 - Try with key parameter
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function TryStop($stopMsg, $label) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    Start-Sleep -Milliseconds 500
    Send- '{"t":"launch","product_id":73}'
    Start-Sleep -Milliseconds 500
    
    Write-Host "`n$label" -ForegroundColor Yellow
    Write-Host "  $stopMsg" -ForegroundColor DarkGray
    Send- $stopMsg
    
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") {
                    Write-Host "  RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok -eq $true) { "Green" } else { "Red" })
                } elseif ($p.t -eq "scr_list_res") {
                    $c8 = $p.instances | Where-Object { $_.id -eq "0:client_8" }
                    if ($c8) { Write-Host "  client_8 state=$($c8.state)" -ForegroundColor $(if ($c8.state -eq "offline") { "Green" } else { "Yellow" }) }
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    $ws.Dispose()
}

# Try with various key formats
TryStop '{"t":"instance_stop","id":"0:client_8","key":"0:client_8"}' "key=0:client_8"
TryStop '{"t":"instance_stop","id":"0:client_8","k":"0:client_8"}' "k=0:client_8"
TryStop '{"t":"instance_stop","id":"0:client_8","key":"client_8"}' "key=client_8"
TryStop '{"t":"instance_stop","id":"0:client_8","apikey":"0:client_8"}' "apikey"
TryStop '{"t":"stop","id":"0:client_8","key":"0:client_8"}' "stop+key"
TryStop '{"t":"instance_stop","id":"0:client_8","token":"0:client_8"}' "token"
TryStop '{"t":"instance_stop","id":"0:client_8","auth":"0:client_8"}' "auth"
TryStop '{"t":"instance_stop","id":"0:client_8","secret":"0:client_8"}' "secret"

Write-Host "`nDone!" -ForegroundColor Cyan
