#RemoteClickRow.ps1 - Click More choices on a specific ROW index
param(
    [int]$Row = 20,
    [switch]$StopAfterMenu
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

function Send-($msg) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
}

function RecvOne {
    $buf = New-Object byte[] 1048576
    $ms = New-Object System.IO.MemoryStream
    $more = $true
    while ($more -and $ws.State -eq "Open") {
        try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false }
    }
    if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }
    $ms.Dispose(); return $null
}

function RecvDrain {
    $all = @()
    while ($ws.State -eq "Open") {
        $buf = New-Object byte[] 1048576
        try {
            $ms = New-Object System.IO.MemoryStream
            $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $all += $p }; $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $all
}

function SendClick($x, $y) {
    Send- (@{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true } | ConvertTo-Json -Compress)
    Start-Sleep -Milliseconds 80
    Send- (@{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false } | ConvertTo-Json -Compress)
}

function SendWheel($delta) {
    Send- (@{ t = "scr_input"; idx = 0; dt = "wheel"; delta = $delta } | ConvertTo-Json -Compress)
}

# Connect
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
$p1 = RecvOne
Write-Host "Caps -> $($p1.t)" -ForegroundColor Green

Send- '{"t":"launch","product_id":73}'
$p2 = RecvOne
Write-Host "Launch -> $($p2.t)" -ForegroundColor Green

# Trigger snapshot
SendClick 300 70
Start-Sleep -Seconds 1
$allMsgs = RecvDrain
$snapshot = $null
foreach ($m in $allMsgs) { if ($m.t -eq "snapshot") { $snapshot = $m } }
if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }
Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find list
$list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1
$rowH = $list.r[3] / $list.visCount
Write-Host "List: visFrom=$($list.visFrom) rowH=$rowH" -ForegroundColor Cyan

# Find the target item
$targetItem = $list.rows | Where-Object { $_.r -eq $Row } | Select-Object -First 1
if (-not $targetItem) { Write-Host "Row $Row not found!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

$name = if ($targetItem.c.Count -gt 1) { $targetItem.c[1] } else { "?" }
Write-Host "Target: row=$Row name=$name checked=$($targetItem.checked)" -ForegroundColor Green

# Scroll if needed
if ($Row -lt $list.visFrom -or $Row -ge ($list.visFrom + $list.visCount)) {
    Write-Host "Scrolling to row $Row..." -ForegroundColor Yellow
    $listCX = $list.r[0] + ($list.r[2] / 2)
    $listCY = $list.r[1] + ($list.r[3] / 2)
    SendClick $listCX $listCY
    Start-Sleep -Milliseconds 300
    
    $diff = $Row - $list.visFrom
    $dir = if ($diff -lt 0) { 3 } else { -3 }
    $count = [Math]::Abs($diff) + 2
    for ($i = 0; $i -lt $count; $i++) { SendWheel $dir; Start-Sleep -Milliseconds 150 }
    
    Start-Sleep -Seconds 1
    $newMsgs = RecvDrain
    foreach ($m in $newMsgs) {
        if ($m.t -eq "snapshot") { 
            $snapshot = $m
            $list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1
        }
    }
    $rowH = $list.r[3] / $list.visCount
    Write-Host "After scroll: visFrom=$($list.visFrom)" -ForegroundColor Gray
}

# Click More choices (column 3)
$clickX = $list.r[0] + 19 + 120 + 105 + 13
$rowIdx = $Row - $list.visFrom
$clickY = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)

Write-Host "Click at ($clickX, $clickY)" -ForegroundColor Yellow
SendClick $clickX $clickY

Start-Sleep -Seconds 2
$menuMsgs = RecvDrain
$snap2 = $null
foreach ($m in $menuMsgs) { if ($m.t -eq "snapshot") { $snap2 = $m } }

if ($snap2) {
    Write-Host "`n=== MENU! gen=$($snap2.gen) ===" -ForegroundColor Green
    $snap2 | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_menu.json" -Encoding UTF8
    
    # Scan all children for menu items
    function Show-Tree($node, $depth) {
        $indent = "  " * $depth
        $txt = if ($node.text) { $node.text } elseif ($node.title) { $node.title } else { "" }
        $vis = if ($node.vis -eq $false) { " [HIDDEN]" } else { "" }
        Write-Host "$indent $($node.kind) id=$($node.id) '$txt' r=$($node.r -join ',')$vis" -ForegroundColor $(if ($txt -and $txt -match "tat|dung|stop|close") { "Red" } elseif ($depth -gt 0) { "Gray" } else { "Cyan" })
        if ($node.children) { foreach ($c in $node.children) { Show-Tree $c ($depth + 1) } }
    }
    Show-Tree $snap2.b 0
} else {
    Write-Host "No menu appeared" -ForegroundColor Red
}

$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
