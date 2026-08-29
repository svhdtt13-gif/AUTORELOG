#TestKeepAlive.ps1 - Check if WS stays open after snapshot
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
Write-Host "1. Connected, state=$($ws.State)" -ForegroundColor Green

$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()
Write-Host "2. Caps sent, state=$($ws.State)" -ForegroundColor Green

$receiveBuf = New-Object byte[] 1048576
$timeout = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream
        $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($receiveBuf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            Write-Host "3. Got: $($p.t), state=$($ws.State)" -ForegroundColor Green
        }
        $ms.Dispose()
    } catch { Write-Host "3b. Recv error: $($_.Exception.Message)" -ForegroundColor Red; break }
}

Write-Host "4. After recv loop, state=$($ws.State)" -ForegroundColor Cyan

# Now try a PING (text message that might be a keepalive)
try {
    $ping = "{`"t`":`"ping`"}"
    $buf = [System.Text.Encoding]::UTF8.GetBytes($ping)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()
    Write-Host "5. Ping sent, state=$($ws.State)" -ForegroundColor Green
} catch {
    Write-Host "5. Ping failed: $($_.Exception.InnerException.Message)" -ForegroundColor Red
}

# Try scr_input with a VERY simple format
try {
    $click = '{"t":"scr_input","idx":0,"dt":"mouse","x":100,"y":100,"btn":"left","down":true}'
    $buf = [System.Text.Encoding]::UTF8.GetBytes($click)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()
    Write-Host "6. scr_input sent, state=$($ws.State)" -ForegroundColor Green
} catch {
    Write-Host "6. scr_input failed: $($_.Exception.InnerException.Message)" -ForegroundColor Red
}

Write-Host "7. Final state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
