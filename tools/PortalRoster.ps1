#PortalRoster.ps1 - Get FULL roster with app rooms from portal
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$portalRoom = "9b2ec1b5372e3ade"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token&disp=web")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"_hello"}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "_roster") {
                Write-Host "`n=== _roster FULL ===" -ForegroundColor Green
                $p | ConvertTo-Json -Depth 20
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\roster.json" -Encoding UTF8
                Write-Host "`nSaved roster.json" -ForegroundColor Green
            }
            elseif ($p.t -eq "_presence") { Write-Host "[_presence] desktop=$($p.desktop)" -ForegroundColor DarkGray }
            elseif ($p.t -eq "catalog") { Write-Host "[catalog] products=$($p.b.products.Count) machine=$($p.b.machine)" -ForegroundColor DarkGray }
            else { Write-Host "[$($p.t)]" -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

$ws.Dispose()