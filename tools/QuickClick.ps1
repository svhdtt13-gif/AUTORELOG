#QuickClick.ps1 - Simple click test
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
Write-Host "Connected" -ForegroundColor Green

$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
Write-Host "Caps sent" -ForegroundColor Green

# Receive snapshot
$receiveBuf = New-Object byte[] 1048576
$snapshot = $null
$timeout = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream
        $more = $true
        while ($more -and $ws.State -eq "Open") {
            $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($result.AsyncWaitHandle.WaitOne(1000)) {
                $ms.Write($receiveBuf, 0, $result.Result.Count)
                $more = -not $result.Result.EndOfMessage
            } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snapshot = $p; Write-Host "Snapshot gen=$($p.gen)" -ForegroundColor Green }
        }
        $ms.Dispose()
    } catch { break }
}

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

$list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1

# Click on first visible row (row 20, visIdx=0)
$clickX = 257  # column 3 center
$clickY = 12   # row 20 center (list top=3 + rowH/2)

Write-Host "Clicking ($clickX, $clickY)..." -ForegroundColor Yellow

$down = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = 257; y = 12; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($down)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()
Write-Host "down sent" -ForegroundColor DarkGray

Start-Sleep -Milliseconds 80

$up = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = 257; y = 12; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($up)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()
Write-Host "up sent" -ForegroundColor DarkGray

# Try to receive for 5 seconds
Start-Sleep -Seconds 2
$timeout2 = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(2000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            Write-Host "Recv: $($msg.Substring(0, [Math]::Min(200, $msg.Length)))" -ForegroundColor DarkGray
        } else {
            Write-Host "No more data" -ForegroundColor DarkGray
            break
        }
    } catch {
        Write-Host "Recv error: $($_.Exception.Message)" -ForegroundColor Red
        break
    }
}

Write-Host "State: $($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
