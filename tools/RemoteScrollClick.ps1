#RemoteScrollClick.ps1 - Scroll list then click options
param(
    [string]$ClientName = "",
    [string]$Action = "options"  # options, stop
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

$list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1

# Find target
$targetRow = -1
foreach ($item in $list.rows) {
    if ($item.c -and $item.c.Count -gt 1) {
        if ($item.c[1].Trim() -like "*$ClientName*" -or $ClientName -like "*$($item.c[1].Trim())*") {
            $targetRow = $item.r
            Write-Host "Found: $($item.c[1].Trim()) at row $targetRow" -ForegroundColor Green
            break
        }
    }
}

if ($targetRow -lt 0) {
    Write-Host "Not found: $ClientName" -ForegroundColor Red
    $ws.Dispose(); exit 1
}

# Check if visible
$visFrom = $list.visFrom
$visCount = $list.visCount
$rowH = $list.r[3] / $visCount

Write-Host "List: visFrom=$visFrom visCount=$visCount rowH=$rowH" -ForegroundColor Gray

function Send-Mouse($x, $y) {
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($d)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($u)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Send-Wheel($delta) {
    $w = @{ t = "scr_input"; idx = 0; dt = "wheel"; delta = $delta; lgen = $snapshot.gen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($w)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

# Calculate list center for clicking/scrolling
$listCenterX = $list.r[0] + ($list.r[2] / 2)
$listCenterY = $list.r[1] + ($list.r[3] / 2)

if ($targetRow -lt $visFrom -or $targetRow -ge ($visFrom + $visCount)) {
    Write-Host "Row $targetRow not visible, scrolling..." -ForegroundColor Yellow
    
    # Scroll up to make target visible
    $scrollAmount = $visFrom - $targetRow
    $wheelClicks = [Math]::Ceiling($scrollAmount / 3) * -1  # negative = scroll up
    
    Write-Host "Scrolling $wheelClicks clicks (from row $visFrom to $targetRow)" -ForegroundColor Gray
    
    # Click on list first to focus it
    Send-Mouse $listCenterX $listCenterY
    Start-Sleep -Milliseconds 200
    
    # Scroll up
    for ($i = 0; $i -lt [Math]::Abs($wheelClicks); $i++) {
        Send-Wheel 3  # scroll up
        Start-Sleep -Milliseconds 100
    }
    
    Start-Sleep -Seconds 1
    
    # Re-receive snapshot to get updated scroll position
    $timeout2 = [DateTime]::UtcNow.AddSeconds(3)
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($result.AsyncWaitHandle.WaitOne(500) -and $result.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
                try {
                    $p = $msg | ConvertFrom-Json
                    if ($p.t -eq "snapshot") { $snapshot = $p; $list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1 }
                    if ($p.t -eq "delta") {
                        # Apply delta to update list
                        if ($p.b -and $p.b.ops) {
                            foreach ($op in $p.b.ops) {
                                if ($op.op -eq "set" -and $op.k -like "*/scrollPos") { $list.scrollPos = $op.v }
                                if ($op.op -eq "set" -and $op.k -like "*/visFrom") { $list.visFrom = $op.v }
                            }
                        }
                    }
                } catch {}
            }
        } catch { break }
    }
    
    $visFrom = $list.visFrom
    Write-Host "After scroll: visFrom=$visFrom" -ForegroundColor Gray
}

# Now click on the row
$rowIndex = $targetRow - $list.visFrom
$clickY = $list.r[1] + ($rowIndex * $rowH) + ($rowH / 2)

# Column 3 (More choices): X = listX + 19 + 120 + 105 + 13
$clickX = $list.r[0] + 19 + 120 + 105 + 13

Write-Host "Clicking 'More choices' at ($clickX, $clickY) for row $targetRow" -ForegroundColor Yellow
Send-Mouse $clickX $clickY

Write-Host "Clicked! Check remote for menu." -ForegroundColor Green

Start-Sleep -Seconds 2
$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
