#TestPortalControl.ps1 - Try through portal room
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session

$rooms = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_rooms.json" | ConvertFrom-Json

# Try both portal and app rooms
foreach ($roomName in @("portalRoom", "appRoom")) {
    $roomId = $rooms.$roomName
    Write-Host "`n=== $roomName ($roomId) ===" -ForegroundColor Cyan
    
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$roomId&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    
    # Try different caps
    foreach ($capsExtra in @('', ',"ctrl":1', ',"mute":0', ',"mute":1')) {
        $caps = '{"t":"caps","proto":3,"gen":1,"actres":1' + $capsExtra + '}'
        Send- $caps
        Start-Sleep -Milliseconds 500
        
        # Collect messages
        $buf = New-Object byte[] 1048576
        $msgs = @()
        $timeout = [DateTime]::UtcNow.AddSeconds(2)
        while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
            try {
                $ms = New-Object System.IO.MemoryStream; $more = $true
                while ($more -and $ws.State -eq "Open") {
                    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
                }
                if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $msgs += $p }; $ms.Dispose() } else { $ms.Dispose(); break }
            } catch { break }
        }
        
        $roster = $msgs | Where-Object { $_.t -eq "_roster" } | Select-Object -First 1
        if ($roster) {
            $caps = $roster.b.PSObject.Properties.Name -join ','
            Write-Host "  caps=$capsExtra roster_keys: $caps" -ForegroundColor Gray
            
            # Check for control-related fields
            if ($roster.b.ctrl -ne $null) { Write-Host "  ctrl=$($roster.b.ctrl)" -ForegroundColor Green }
            if ($roster.b.mute -ne $null) { Write-Host "  mute=$($roster.b.mute)" -ForegroundColor Green }
            if ($roster.b.role -ne $null) { Write-Host "  role=$($roster.b.role)" -ForegroundColor Green }
            if ($roster.b.perm -ne $null) { Write-Host "  perm=$($roster.b.perm)" -ForegroundColor Green }
            if ($roster.b.key -ne $null) { Write-Host "  key=$($roster.b.key)" -ForegroundColor Green }
            
            # Show full roster
            Write-Host "  Full roster:" -ForegroundColor DarkGray
            $roster.b | ConvertTo-Json -Depth 3 | Write-Host -ForegroundColor DarkGray
        }
        
        if ($ws.State -ne "Open") { break }
    }
    
    $ws.Dispose()
}

Write-Host "`nDone!" -ForegroundColor Cyan
