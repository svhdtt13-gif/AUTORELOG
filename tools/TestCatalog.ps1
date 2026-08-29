#TestCatalog.ps1 - Get catalog and try stop from portal
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$portalRoom = "9b2ec1b5372e3ade"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$portalRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'

# Collect all
$buf = New-Object byte[] 1048576
$timeout = [DateTime]::UtcNow.AddSeconds(5)
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
                    Write-Host "=== CATALOG ===" -ForegroundColor Green
                    $raw | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\catalog.json" -Encoding UTF8
                    $p | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Cyan
                } else {
                    Write-Host "$($p.t)" -ForegroundColor Gray
                }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

# Now try instance_stop from portal
Write-Host "`n=== Try instance_stop from portal ===" -ForegroundColor Yellow
Send- '{"t":"instance_stop","id":"0:client_8"}'

$timeout2 = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "act_result") {
                    Write-Host "ACT_RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
                } else {
                    Write-Host "$($p.t)" -ForegroundColor Gray
                }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
