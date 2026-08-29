#RemoteControl.ps1 - Connect to remote.360auto.net via WebSocket
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Load session
$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$room = "e1c51deba15917ba"  # App room for Auto Ghost Story

Write-Host "=== CONNECTING TO REMOTE ===" -ForegroundColor Cyan
Write-Host "Room: $room" -ForegroundColor Gray

# Create WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")

$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$room&session=$token")
Write-Host "Connecting to: $uri" -ForegroundColor Gray

try {
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    Write-Host "Connected!" -ForegroundColor Green
    
    # Send caps handshake
    $caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
    $sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
    $sendSeg = New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)
    $ws.SendAsync($sendSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Write-Host "Sent caps handshake" -ForegroundColor Gray
    
    # Receive messages for 5 seconds
    $receiveBuf = New-Object byte[] 65536
    $timeout = [DateTime]::UtcNow.AddSeconds(5)
    
    while ([DateTime]::UtcNow -lt $timeout) {
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Host "WebSocket closed" -ForegroundColor Red
            break
        }
        
        $receiveSeg = New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)
        $result = $ws.ReceiveAsync($receiveSeg, $ct)
        
        if ($result.IsCompleted) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            Write-Host "RECV: $msg" -ForegroundColor Yellow
            
            # Parse and display
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") {
                    Write-Host "`n=== SNAPSHOT ===" -ForegroundColor Cyan
                    Write-Host ($parsed | ConvertTo-Json -Depth 10) -ForegroundColor Gray
                }
            } catch {}
        } else {
            Start-Sleep -Milliseconds 100
        }
    }
    
    Write-Host "`n=== DONE ===" -ForegroundColor Cyan
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
} finally {
    if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
    }
    $ws.Dispose()
}
