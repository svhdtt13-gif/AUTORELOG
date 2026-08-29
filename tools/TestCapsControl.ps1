#TestCapsControl.ps1 - Try different caps capabilities
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function TryCaps($capsMsg, $label) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    
    Send- $capsMsg
    Start-Sleep -Milliseconds 500
    Send- '{"t":"launch","product_id":73}'
    Start-Sleep -Milliseconds 500
    
    Write-Host "`n$label" -ForegroundColor Yellow
    Send- '{"t":"instance_stop","id":"0:client_8"}'
    
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
                    $capsShown = $true
                } elseif ($p.t -eq "_roster") {
                    Write-Host "  roster: $($p.b.PSObject.Properties.Name -join ',')" -ForegroundColor Gray
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    $ws.Dispose()
}

# Try different caps
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"ctrl":1}' "ctrl:1"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"control":1}' "control:1"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"screen":1,"write":1}' "write:1"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"admin":1}' "admin:1"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"role":"controller"}' "role:controller"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"role":"admin"}' "role:admin"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"perm":1}' "perm:1"
TryCaps '{"t":"caps","proto":3,"gen":1,"actres":1,"mute":0,"actres":1}' "mute:0"

Write-Host "`nDone!" -ForegroundColor Cyan
