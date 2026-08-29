#TestKeyboard.ps1 - Try keyboard input via remote
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

# Caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Drain initial messages
$receiveBuf = New-Object byte[] 131072
$timeout = [DateTime]::UtcNow.AddSeconds(3)
$lgen = 1
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(500) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try { $p = $msg | ConvertFrom-Json; if ($p.gen) { $lgen = $p.gen } } catch {}
        }
    } catch { break }
}

Write-Host "lgen=$lgen" -ForegroundColor Gray

function Send-Mouse($x, $y) {
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($d)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($u)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Send-Key($vk) {
    $kd = @{ t = "scr_input"; idx = 0; dt = "key"; vk = $vk; down = $true; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($kd)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    $ku = @{ t = "scr_input"; idx = 0; dt = "key"; vk = $vk; down = $false; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($ku)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

# Test: click somewhere visible first
Write-Host "Clicking center of screen (400,300)..." -ForegroundColor Yellow
try {
    Send-Mouse 400 300
    Write-Host "Mouse click sent OK" -ForegroundColor Green
} catch {
    Write-Host "Mouse click failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Test: send keyboard
Write-Host "Sending Alt+F4..." -ForegroundColor Yellow
try {
    Send-Key 0x12  # VK_MENU (Alt)
    Start-Sleep -Milliseconds 100
    Send-Key 0x73  # VK_F4
    Start-Sleep -Milliseconds 100
    # Release Alt
    $ku = @{ t = "scr_input"; idx = 0; dt = "key"; vk = 0x12; down = $false; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($ku)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Write-Host "Alt+F4 sent OK" -ForegroundColor Green
} catch {
    Write-Host "Key failed: $_" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Check state
Write-Host "WebSocket state: $($ws.State)" -ForegroundColor Cyan

$ws.Dispose()
