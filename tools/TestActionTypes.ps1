#TestActionTypes.ps1 - Try different message types to trigger client options
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
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), "Text", $true, $ct).Wait()

$receiveBuf = New-Object byte[] 1048576
$gen = 0
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
            if ($p.gen) { $gen = $p.gen }
            Write-Host "Got: $($p.t) gen=$gen" -ForegroundColor DarkGray
        }
        $ms.Dispose()
    } catch { break }
}

Write-Host "gen=$gen" -ForegroundColor Cyan

function Send-Test($msg) {
    Write-Host "`nSending: $msg" -ForegroundColor Yellow
    $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
    try {
        $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
        Write-Host "  Sent OK" -ForegroundColor Green
        Start-Sleep -Milliseconds 500
        # Try receive
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($r.AsyncWaitHandle.WaitOne(2000) -and $r.Result.Count -gt 0) {
            $response = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $r.Result.Count)
            Write-Host "  Response: $($response.Substring(0, [Math]::Min(300, $response.Length)))" -ForegroundColor Cyan
        } else {
            Write-Host "  No response, state=$($ws.State)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Error: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
}

# Test various action message types
Send-Test (@{ t = "act"; key = "root/1000#0/row0"; act = 0 } | ConvertTo-Json -Compress)
Send-Test (@{ t = "action"; key = "root/1000#0/row0"; act = 0 } | ConvertTo-Json -Compress)
Send-Test (@{ t = "scr_cmd"; idx = 0; cmd = "context_menu" } | ConvertTo-Json -Compress)
Send-Test (@{ t = "input"; idx = 0; dt = "mouse"; x = 257; y = 12; btn = "left"; down = $true } | ConvertTo-Json -Compress)
Send-Test (@{ t = "scr_mouse"; idx = 0; x = 257; y = 12; btn = "left"; down = $true } | ConvertTo-Json -Compress)
Send-Test (@{ t = "mouse"; idx = 0; x = 257; y = 12; btn = "left"; down = $true } | ConvertTo-Json -Compress)

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
