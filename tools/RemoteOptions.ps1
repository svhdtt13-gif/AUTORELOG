#RemoteOptions.ps1 - Click "More choices" button on client to open options menu
param(
    [string]$ClientName = ""
)

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

# Collect messages
$receiveBuf = New-Object byte[] 1048576
$snapshot = $null
$scrList = $null
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
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") { $snapshot = $parsed }
                if ($parsed.t -eq "scr_list_res") { $scrList = $parsed }
            } catch {}
        }
        $ms.Dispose()
    } catch { break }
}

if (-not $snapshot) {
    Write-Host "No snapshot!" -ForegroundColor Red
    $ws.Dispose()
    exit 1
}

Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find client in list
$list = $null
foreach ($child in $snapshot.b.children) {
    if ($child.kind -eq "list" -and $child.total -gt 10) {
        $list = $child
        break
    }
}

if (-not $list) {
    Write-Host "List not found!" -ForegroundColor Red
    $ws.Dispose()
    exit 1
}

Write-Host "List: id=$($list.id) total=$($list.total) visCount=$($list.visCount) scrollPos=$($list.scrollPos) visFrom=$($list.visFrom)" -ForegroundColor Gray

# Find target client
$targetRow = -1
$targetItem = $null
foreach ($item in $list.rows) {
    if ($item.c -and $item.c.Count -gt 1) {
        $name = $item.c[1].Trim()
        if ($name -like "*$ClientName*" -or $ClientName -like "*$name*") {
            $targetRow = $item.r
            $targetItem = $item
            Write-Host "Found: $name at row $targetRow (checked=$($item.checked))" -ForegroundColor Green
            break
        }
    }
}

if ($targetRow -lt 0) {
    Write-Host "Client '$ClientName' not found!" -ForegroundColor Red
    # Show all clients
    Write-Host "`nAll clients:" -ForegroundColor Yellow
    foreach ($item in $list.rows) {
        if ($item.c -and $item.c.Count -gt 1) {
            $st = if ($item.checked -eq 1) { "[ON]" } else { "[OFF]" }
            Write-Host "  $st row=$($item.r) $($item.c[1])" -ForegroundColor Gray
        }
    }
    $ws.Dispose()
    exit 1
}

# Calculate click position for "More choices" button (column 3)
# List position: r[0]=x, r[1]=y, r[2]=w, r[3]=h
$listX = $list.r[0]
$listY = $list.r[1]
$listH = $list.r[3]

# Column widths: #=19, Giả lập=120, Trạng thái=105, ""=26, Cấp=50, ...
# Column 3 starts at: 19+120+105 = 244, width=26
$col3X = 19 + 120 + 105  # = 244
$col3W = 26
$clickX = $listX + $col3X + ($col3W / 2)  # center of column 3

# Row height
$rowH = $listH / $list.visCount

# Row Y position (relative to list)
$rowIndex = $targetRow - $list.visFrom
$clickY = $listY + ($rowIndex * $rowH) + ($rowH / 2)

Write-Host "Click: ($clickX, $clickY) for row $targetRow" -ForegroundColor Yellow

# Send mouse click
$ct2 = [System.Threading.CancellationToken]::None
$mouseDown = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($mouseDown)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct2).Wait()
Start-Sleep -Milliseconds 50

$mouseUp = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($mouseUp)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct2).Wait()

Write-Host "Clicked! Waiting for menu..." -ForegroundColor Green

# Wait for response/delta
Start-Sleep -Seconds 2
$timeout2 = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct2)
        if ($result.AsyncWaitHandle.WaitOne(500) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") {
                    Write-Host "New snapshot received!" -ForegroundColor Green
                    $parsed | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_click.json" -Encoding UTF8
                } elseif ($parsed.t -eq "delta") {
                    Write-Host "Delta received" -ForegroundColor DarkGray
                }
            } catch {}
        }
    } catch { break }
}

$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
