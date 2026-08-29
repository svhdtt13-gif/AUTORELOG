#TestPortalDirect.ps1 - Connect to portal room directly
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session

# Connect to portal room
$portalRoom = "9b2ec1b5372e3ade"
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None

try {
    $ws.ConnectAsync($uri, $ct).Wait()
    Write-Host "Connected to portal!" -ForegroundColor Green
} catch {
    Write-Host "Connection failed: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    $ws.Dispose()
    exit 1
}

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

# Try with various caps
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Seconds 2

# Collect all messages
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
            if ($p) {
                Write-Host "Got: $($p.t)" -ForegroundColor Gray
                if ($p.t -eq "_roster") {
                    Write-Host "Roster:" -ForegroundColor Cyan
                    $p.b | ConvertTo-Json -Depth 5 | Write-Host -ForegroundColor Cyan
                }
                if ($p.t -eq "snapshot") {
                    Write-Host "Snapshot!" -ForegroundColor Green
                    $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_portal.json" -Encoding UTF8
                }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "State: $($ws.State)" -ForegroundColor Cyan

# Now try to launch from portal
if ($ws.State -eq "Open") {
    Send- '{"t":"launch","product_id":73}'
    Start-Sleep -Seconds 2
    
    $timeout2 = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) {
                    Write-Host "After launch: $($p.t)" -ForegroundColor Gray
                    if ($p.t -eq "snapshot") {
                        Write-Host "Snapshot!" -ForegroundColor Green
                        $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_portal_launch.json" -Encoding UTF8
                    }
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
}

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
