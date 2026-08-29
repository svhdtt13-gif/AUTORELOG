#TestLaunch2.ps1 - Caps -> wait -> launch -> wait -> send commands
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

function Send-($msg) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
}

function RecvAll($seconds) {
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds($seconds)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream
            $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                Write-Host "  $($p.t)" -ForegroundColor DarkGray
                $ms.Dispose()
                return $p
            }
            $ms.Dispose()
        } catch { break }
    }
    return $null
}

# Step 1: Caps
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Write-Host "Caps sent" -ForegroundColor Green
$snap = RecvAll 3
Write-Host "State: $($ws.State)" -ForegroundColor Cyan

if ($ws.State -eq "Open") {
    # Step 2: Launch
    Send- '{"t":"launch","product_id":73}'
    Write-Host "Launch sent" -ForegroundColor Green
    $snap2 = RecvAll 3
    Write-Host "State: $($ws.State)" -ForegroundColor Cyan
}

if ($ws.State -eq "Open") {
    # Step 3: Try scr_input NOW
    Write-Host "`nTrying scr_input..." -ForegroundColor Yellow
    Send- '{"t":"scr_input","idx":0,"dt":"mouse","x":100,"y":100,"btn":"left","down":true}'
    Write-Host "scr_input down sent, state=$($ws.State)" -ForegroundColor Green
    Start-Sleep -Milliseconds 100
    Send- '{"t":"scr_input","idx":0,"dt":"mouse","x":100,"y":100,"btn":"left","down":false}'
    Write-Host "scr_input up sent, state=$($ws.State)" -ForegroundColor Green
    
    $r = RecvAll 3
    Write-Host "Response: $($r.t)" -ForegroundColor Cyan
}

Write-Host "Final: $($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
