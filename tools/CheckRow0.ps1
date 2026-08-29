#CheckRow0.ps1 - Reconnect and check row 0 checked state
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
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$timeout = [DateTime]::UtcNow.AddSeconds(6)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                Write-Host "snapshot gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor DarkGray
                foreach ($n in $p.b.children) {
                    if ($n.key -eq "root/1000#0") {
                        Write-Host "`n=== Client list state ===" -ForegroundColor Green
                        foreach ($row in $n.rows) {
                            $state = if ($row.checked -eq 1) { "RUNNING" } else { "off" }
                            Write-Host "  row $($row.r) checked=$($row.checked)  [$state]" -ForegroundColor $(if ($row.checked -eq 1) { "Green" } else { "DarkGray" })
                        }
                        $p | ConvertTo-Json -Depth 10 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_current.json" -Encoding UTF8
                    }
                }
                $ws.Dispose(); break
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
Write-Host "Final: $($ws.State)" -ForegroundColor DarkGray
$ws.Dispose()