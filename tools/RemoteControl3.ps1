#RemoteControl3.ps1 - Debug WebSocket close
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session

$room = "9b2ec1b5372e3ade"

Write-Host "=== DEBUG WEBSOCKET ===" -ForegroundColor Cyan

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")

$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$room&session=$token")

$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "State: $($ws.State)" -ForegroundColor Green

# Send caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
Write-Host "Sent caps" -ForegroundColor Gray

# Try to receive with better error handling
$receiveBuf = New-Object byte[] 131072

for ($i = 0; $i -lt 20; $i++) {
    try {
        $receiveSeg = New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)
        $result = $ws.ReceiveAsync($receiveSeg, $ct)
        
        # Wait up to 2 seconds
        if ($result.AsyncWaitHandle.WaitOne(2000)) {
            if ($result.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
                Write-Host "MSG $i : $msg" -ForegroundColor Yellow
            }
            
            if ($result.Result.EndOfMessage -eq $false) {
                Write-Host "Partial message..." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "Timeout on receive $i" -ForegroundColor DarkGray
        }
        
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Host "State changed to: $($ws.State)" -ForegroundColor Red
            break
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        break
    }
}

Write-Host "`nFinal state: $($ws.State)" -ForegroundColor Cyan
if ($ws.CloseStatus) {
    Write-Host "Close status: $($ws.CloseStatus) - $($ws.CloseStatusDescription)" -ForegroundColor Red
}

$ws.Dispose()
