#DebugRemote.ps1 - Debug remote data
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

$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$receiveBuf = New-Object byte[] 131072
$timeout = [DateTime]::UtcNow.AddSeconds(5)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(1000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "scr_list_res") {
                    Write-Host "=== SCR_LIST_RES ===" -ForegroundColor Green
                    Write-Host ($parsed | ConvertTo-Json -Depth 5) -ForegroundColor Gray
                }
                if ($parsed.t -eq "snapshot") {
                    Write-Host "=== SNAPSHOT (first 2000 chars) ===" -ForegroundColor Cyan
                    $snapJson = $parsed | ConvertTo-Json -Depth 10
                    Write-Host $snapJson.Substring(0, [Math]::Min(2000, $snapJson.Length)) -ForegroundColor Gray
                }
            } catch {}
        }
    } catch { break }
}

$ws.Dispose()
