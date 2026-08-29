#PortalConnect.ps1 - Connect to portal room, get catalog, find app room for product 73
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$portalRoom = "9b2ec1b5372e3ade"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token&disp=web")
$ct = [System.Threading.CancellationToken]::None
try { $ws.ConnectAsync($uri, $ct).Wait() } catch { Write-Host "Connect failed: $($_.Exception.InnerException.Message)" -ForegroundColor Red; exit 1 }
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

# Send _hello like the browser
Write-Host "Sending _hello..." -ForegroundColor Yellow
Send- '{"t":"_hello"}'

# Collect for 8 seconds
$timeout = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "catalog") {
                    Write-Host "`n=== CATALOG RECEIVED ===" -ForegroundColor Green
                    if ($p.b) {
                        Write-Host "  b type: $($p.b.GetType().Name)" -ForegroundColor Gray
                        if ($p.b.machine) { Write-Host "  machine: $($p.b.machine)" -ForegroundColor Cyan }
                        if ($p.b.apps) {
                            Write-Host "  apps: $($p.b.apps.Count)" -ForegroundColor Cyan
                            foreach ($app in $p.b.apps) {
                                $room = if ($app.room) { $app.room } else { "?" }
                                $pid = if ($app.product_id) { $app.product_id } else { "?" }
                                $name = if ($app.name) { $app.name } else { "?" }
                                $state = if ($app.state) { $app.state } else { "?" }
                                Write-Host "    id=$pid name='$name' room=$room state=$state" -ForegroundColor Cyan
                            }
                        }
                    }
                    $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\catalog.json" -Encoding UTF8
                    Write-Host "  Saved catalog.json" -ForegroundColor Green
                }
                elseif ($p.t -eq "_presence") { Write-Host "[_presence] desktop=$($p.desktop)" -ForegroundColor Cyan }
                elseif ($p.t -eq "_roster") { Write-Host "[_roster]" -ForegroundColor DarkGray }
                elseif ($p.t -eq "_session") { Write-Host "[_session] ADh session=$($p.s)" -ForegroundColor Green; $p | ConvertTo-Json | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\portal_session.json" -Encoding UTF8 }
                else { Write-Host "[$($p.t)]" -ForegroundColor Gray }
            } else {
                Write-Host "[raw] $raw" -ForegroundColor Yellow
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { Write-Host "Err: $($_.Exception.Message)" -ForegroundColor Red; break }
}

Write-Host "`nFinal state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()