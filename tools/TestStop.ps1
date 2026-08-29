#TestStop.ps1 - Try stop command to close client
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

# Send caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Receive data
$receiveBuf = New-Object byte[] 131072
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(500) -and $result.Result.Count -gt 0) {}
    } catch { break }
}

# Try different stop approaches
Write-Host "=== APPROACH 1: stop product 73 ===" -ForegroundColor Yellow
$stop = @{ t = "stop"; product_id = 73; force = $false } | ConvertTo-Json -Compress
Write-Host "Sending: $stop" -ForegroundColor Gray
$buf = [System.Text.Encoding]::UTF8.GetBytes($stop)
try {
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Write-Host "Sent OK" -ForegroundColor Green
} catch {
    Write-Host "Send failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 3

# Check response
try {
    $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
    if ($result.AsyncWaitHandle.WaitOne(2000) -and $result.Result.Count -gt 0) {
        $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
        Write-Host "Response: $msg" -ForegroundColor Cyan
    }
} catch {}

$ws.Dispose()
