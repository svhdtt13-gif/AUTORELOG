#TestLaunch.ps1 - Try sending launch after caps
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

function Send-($msg) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
}

function Recv- {
    $buf = New-Object byte[] 1048576
    $ms = New-Object System.IO.MemoryStream
    $more = $true
    while ($more -and $ws.State -eq "Open") {
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
        if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
    }
    $result = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    $ms.Dispose()
    return $result
}

# 1. Connect + caps
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Write-Host "1. Caps sent, state=$($ws.State)" -ForegroundColor Green

# 2. Receive all initial messages
Start-Sleep -Seconds 2
while ($ws.State -eq "Open") {
    try {
        $buf = New-Object byte[] 1048576
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
        if ($r.AsyncWaitHandle.WaitOne(1000) -and $r.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
            $p = $msg | ConvertFrom-Json -ErrorAction SilentlyContinue
            Write-Host "  Got: $($p.t)" -ForegroundColor DarkGray
        } else {
            break
        }
    } catch { break }
}
Write-Host "2. State after initial: $($ws.State)" -ForegroundColor Cyan

if ($ws.State -ne "Open") {
    Write-Host "Connection closed! Trying different approach..." -ForegroundColor Red
    $ws.Dispose()
    
    # Try with portal room instead
    $ws2 = New-Object System.Net.WebSockets.ClientWebSocket
    $ws2.Options.SetRequestHeader("Authorization", "Bearer $token")
    $portalRoom = "9b2ec1b5372e3ade"
    $uri2 = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token")
    $ws2.ConnectAsync($uri2, $ct).Wait()
    Write-Host "3. Portal connected, state=$($ws2.State)" -ForegroundColor Green
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    
    # Collect all messages
    Start-Sleep -Seconds 3
    while ($ws2.State -eq "Open") {
        try {
            $buf = New-Object byte[] 1048576
            $r = $ws2.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000) -and $r.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
                $p = $msg | ConvertFrom-Json -ErrorAction SilentlyContinue
                Write-Host "  Got: $($p.t) keys=$($p.PSObject.Properties.Name -join ',')" -ForegroundColor DarkGray
            } else { break }
        } catch { break }
    }
    Write-Host "4. Portal state: $($ws2.State)" -ForegroundColor Cyan
    $ws2.Dispose()
} else {
    # Try send launch
    Send- '{"t":"launch","product_id":73}'
    Write-Host "3. Launch sent, state=$($ws.State)" -ForegroundColor Green
    
    Start-Sleep -Seconds 2
    while ($ws.State -eq "Open") {
        try {
            $buf = New-Object byte[] 1048576
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000) -and $r.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
                $p = $msg | ConvertFrom-Json -ErrorAction SilentlyContinue
                Write-Host "  Got: $($p.t)" -ForegroundColor DarkGray
            } else { break }
        } catch { break }
    }
    Write-Host "4. After launch: $($ws.State)" -ForegroundColor Cyan
    $ws.Dispose()
}
