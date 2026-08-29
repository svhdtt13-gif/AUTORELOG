#CaptureSnapshotFull.ps1 - Capture FULL snapshot with caps field
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
                Write-Host "`n=== SNAPSHOT top-level keys ===" -ForegroundColor Green
                $p.PSObject.Properties.Name | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
                Write-Host "`n=== caps field ===" -ForegroundColor Green
                if ($null -ne $p.caps) { $p.caps | ConvertTo-Json -Depth 10 } else { Write-Host "  (no caps field)" -ForegroundColor Yellow }
                Write-Host "`n=== gen/sepoch/actres===" -ForegroundColor Green
                Write-Host "  gen=$($p.gen) sepoch=$($p.sepoch)"
                $p | ConvertTo-Json -Depth 4 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_head.json" -Encoding UTF8
                $top = @{ t=$p.t; gen=$p.gen; sepoch=$p.sepoch; caps=$p.caps; ver=$p.ver } | ConvertTo-Json -Depth 8 -Compress
                Set-Content "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_caps.json" $top
                Write-Host "`n=== node keys (root children) ===" -ForegroundColor Green
                if ($p.b) {
                    Write-Host "b has keys: $(($p.b.PSObject.Properties.Name) -join ', ')" -ForegroundColor Cyan
                    if ($p.b.root) {
                        Write-Host "root type: $($p.b.root.GetType().Name)"
                        if ($p.b.root.children) {
                            Write-Host "children count: $($p.b.root.children.Count)"
                            foreach ($c in $p.b.root.children) { Write-Host "  child key=$($c.key) kind=$($c.kind) text=$(($c.text -replace '[^\x20-\x7E]','.'))" -ForegroundColor DarkGray }
                        }
                    }
                } else { Write-Host "  b null" -ForegroundColor Yellow }
                $ws.Dispose(); break
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
$ws.Dispose()