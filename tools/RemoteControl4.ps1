#RemoteControl4.ps1 - Connect to app room, read clients, send commands
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session

$appRoom = "e1c51deba15917ba"

Write-Host "=== CONNECTING TO APP ROOM ===" -ForegroundColor Cyan

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")

$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")

$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected! State: $($ws.State)" -ForegroundColor Green

# Send caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Receive for 8 seconds
$receiveBuf = New-Object byte[] 131072
$timeout = [DateTime]::UtcNow.AddSeconds(8)

while ([DateTime]::UtcNow -lt $timeout) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        
        if ($result.AsyncWaitHandle.WaitOne(2000)) {
            if ($result.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
                
                try {
                    $parsed = $msg | ConvertFrom-Json
                    $t = $parsed.t
                    
                    if ($t -eq "snapshot") {
                        Write-Host "`n=== SNAPSHOT ===" -ForegroundColor Green
                        Write-Host ($parsed | ConvertTo-Json -Depth 10) -ForegroundColor Gray
                    } elseif ($t -eq "childList") {
                        Write-Host "`n=== CHILDLIST ===" -ForegroundColor Green
                        Write-Host ($parsed | ConvertTo-Json -Depth 10) -ForegroundColor Gray
                    } elseif ($t -eq "delta") {
                        Write-Host "Delta" -ForegroundColor DarkGray
                    } elseif ($t -eq "act_result") {
                        Write-Host "`n=== ACT_RESULT ===" -ForegroundColor Yellow
                        Write-Host ($parsed | ConvertTo-Json -Depth 10) -ForegroundColor Gray
                    } else {
                        Write-Host "MSG [$t]: $($msg.Substring(0, [Math]::Min(1000, $msg.Length)))" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "RAW: $($msg.Substring(0, [Math]::Min(500, $msg.Length)))" -ForegroundColor Gray
                }
            }
        }
        
        if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            Write-Host "State: $($ws.State)" -ForegroundColor Red
            break
        }
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        break
    }
}

# Now try to send a launch command
Write-Host "`n=== SEND LAUNCH COMMAND ===" -ForegroundColor Cyan
$launch = @{ t = "launch"; product_id = 73 } | ConvertTo-Json -Compress
Write-Host "Sending: $launch" -ForegroundColor Gray
$launchBuf = [System.Text.Encoding]::UTF8.GetBytes($launch)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$launchBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Wait for response
Start-Sleep -Seconds 3
$ws.Dispose()
Write-Host "Done" -ForegroundColor Cyan
