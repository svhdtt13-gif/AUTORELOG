#TestClickVisible.ps1 - Click "More choices" on a visible row to verify coordinates
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
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$receiveBuf = New-Object byte[] 1048576
$snapshot = $null
$timeout = [DateTime]::UtcNow.AddSeconds(8)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $ms = New-Object System.IO.MemoryStream
        $more = $true
        while ($more -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($result.AsyncWaitHandle.WaitOne(1000)) {
                $ms.Write($receiveBuf, 0, $result.Result.Count)
                $more = -not $result.Result.EndOfMessage
            } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            try { $p = $msg | ConvertFrom-Json; if ($p.t -eq "snapshot") { $snapshot = $p } } catch {}
        }
        $ms.Dispose()
    } catch { break }
}

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find the list
$list = $null
foreach ($child in $snapshot.b.children) {
    if ($child.kind -eq "list" -and $child.total -gt 10) {
        $list = $child
        break
    }
}

Write-Host "List: r=$($list.r -join ',') visFrom=$($list.visFrom) visCount=$($list.visCount)" -ForegroundColor Cyan
$rowH = $list.r[3] / $list.visCount
Write-Host "RowH: $rowH" -ForegroundColor Gray

# Show visible rows
Write-Host "`nVisible rows:" -ForegroundColor Yellow
foreach ($item in $list.rows) {
    $rowIdx = $item.r - $list.visFrom
    if ($rowIdx -ge 0 -and $rowIdx -lt $list.visCount) {
        $name = if ($item.c.Count -gt 1) { $item.c[1] } else { "?" }
        $y = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)
        Write-Host "  row=$($item.r) visIdx=$rowIdx name=$name checked=$($item.checked) -> Y=$y" -ForegroundColor Gray
    }
}

# Click "More choices" on first visible running row
$targetItem = $null
foreach ($item in $list.rows) {
    if ($item.checked -eq 1 -and ($item.r - $list.visFrom) -ge 0) {
        $targetItem = $item
        break
    }
}

if (-not $targetItem) {
    Write-Host "No visible running client!" -ForegroundColor Red
    # Just click first visible row
    $targetItem = $list.rows | Where-Object { ($_.r - $list.visFrom) -ge 0 } | Select-Object -First 1
}

$rowIdx = $targetItem.r - $list.visFrom
$clickY = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)
# Column 3 "More choices": 19 + 120 + 105 + 13 = 257
$clickX = $list.r[0] + 19 + 120 + 105 + 13

$name = if ($targetItem.c.Count -gt 1) { $targetItem.c[1] } else { "?" }
Write-Host "`nClick 'More' on: $name at ($clickX, $clickY)" -ForegroundColor Green

# Send click
$mouseDown = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($mouseDown)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
Start-Sleep -Milliseconds 50

$mouseUp = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($mouseUp)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

Write-Host "Clicked! Waiting for response..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Check for new snapshot
$timeout2 = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(500) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $p = $msg | ConvertFrom-Json
                Write-Host "Got: $($p.t)" -ForegroundColor DarkGray
                if ($p.t -eq "snapshot") {
                    Write-Host "New snapshot!" -ForegroundColor Green
                    $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_click.json" -Encoding UTF8
                    # Look for menu/popup
                    if ($p.b.children) {
                        foreach ($c in $p.b.children) {
                            Write-Host "  child: kind=$($c.kind) id=$($c.id) cls=$($c.cls) title=$($c.title)" -ForegroundColor Gray
                            if ($c.children) {
                                foreach ($cc in $c.children) {
                                    Write-Host "    sub: kind=$($cc.kind) id=$($cc.id) text=$($cc.text)" -ForegroundColor Gray
                                }
                            }
                        }
                    }
                }
            } catch {}
        }
    } catch { break }
}

$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
