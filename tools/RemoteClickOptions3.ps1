#RemoteClickOptions3.ps1 - Fixed: consume fewer messages in caps/launch phases
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

function Send-($msg) {
    $b = [System.Text.Encoding]::UTF8.GetBytes($msg)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
}

function RecvOne {
    $buf = New-Object byte[] 1048576
    $ms = New-Object System.IO.MemoryStream
    $more = $true
    while ($more -and $ws.State -eq "Open") {
        try {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        } catch { $more = $false }
    }
    if ($ms.Length -gt 0) {
        $msg = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
        $ms.Dispose()
        return ($msg | ConvertFrom-Json -ErrorAction SilentlyContinue)
    }
    $ms.Dispose()
    return $null
}

function RecvDrain {
    $buf = New-Object byte[] 1048576
    $all = @()
    while ($ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream
            $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) { $all += $p }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
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

# Step 1: Caps (consume only _presence)
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
$p1 = RecvOne
Write-Host "1. Caps -> $($p1.t)" -ForegroundColor Green

# Step 2: Launch (consume only _roster)  
Send- '{"t":"launch","product_id":73}'
$p2 = RecvOne
Write-Host "2. Launch -> $($p2.t)" -ForegroundColor Green

# Step 3: Now send a dummy mouse click to trigger snapshot
Write-Host "3. Triggering snapshot via dummy click..." -ForegroundColor Yellow
SendClick 300 70
Start-Sleep -Seconds 1

# Drain all pending messages to find snapshot
$allMsgs = RecvDrain
$snapshot = $null
foreach ($m in $allMsgs) {
    if ($m.t -eq "snapshot") { $snapshot = $m }
    Write-Host "  Got: $($m.t)" -ForegroundColor DarkGray
}

if (-not $snapshot) {
    Write-Host "No snapshot, trying another click..." -ForegroundColor Yellow
    SendClick 300 70
    Start-Sleep -Seconds 1
    $allMsgs2 = RecvDrain
    foreach ($m in $allMsgs2) {
        if ($m.t -eq "snapshot") { $snapshot = $m }
        Write-Host "  Got: $($m.t)" -ForegroundColor DarkGray
    }
}

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }
Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find list
$list = $null
foreach ($child in $snapshot.b.children) {
    if ($child.kind -eq "list" -and $child.total -gt 10) { $list = $child; break }
}
if (-not $list) { Write-Host "No list!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

Write-Host "List: visFrom=$($list.visFrom) visCount=$($list.visCount) total=$($list.total)" -ForegroundColor Cyan

# Find target
$targetRow = -1
foreach ($item in $list.rows) {
    if ($item.c.Count -gt 1) {
        $name = $item.c[1].Trim()
        if ($name -like "*$ClientName*" -or $ClientName -like "*$name*") {
            $targetRow = $item.r
            Write-Host "Found: $name row=$targetRow checked=$($item.checked)" -ForegroundColor Green
            break
        }
    }
}

if ($targetRow -lt 0) {
    Write-Host "Not found: $ClientName" -ForegroundColor Red
    $list.rows | Where-Object { $_.c.Count -gt 1 } | ForEach-Object {
        $st = if ($_.checked -eq 1) { "[ON]" } else { "[OFF]" }
        Write-Host "  $st row=$($_.r) $($_.c[1])" -ForegroundColor Gray
    }
    $ws.Dispose(); exit 1
}

# Calculate positions
$rowH = $list.r[3] / $list.visCount
$clickX = $list.r[0] + 19 + 120 + 105 + 13  # column 3 center

# Scroll if needed
if ($targetRow -lt $list.visFrom -or $targetRow -ge ($list.visFrom + $list.visCount)) {
    Write-Host "Scrolling from visFrom=$($list.visFrom) to row $targetRow..." -ForegroundColor Yellow
    
    $listCX = $list.r[0] + ($list.r[2] / 2)
    $listCY = $list.r[1] + ($list.r[3] / 2)
    SendClick $listCX $listCY
    Start-Sleep -Milliseconds 300
    
    $diff = $targetRow - $list.visFrom
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
    Write-Host "After scroll: visFrom=$($list.visFrom)" -ForegroundColor Gray
}

# Click More choices
$rowIdx = $targetRow - $list.visFrom
$clickY = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)

Write-Host "Click 'More' at ($clickX, $clickY)" -ForegroundColor Yellow
SendClick $clickX $clickY

# Wait for menu
Start-Sleep -Seconds 2
$menuMsgs = RecvDrain
$snap2 = $null
foreach ($m in $menuMsgs) {
    if ($m.t -eq "snapshot") { $snap2 = $m }
    Write-Host "  Got: $($m.t)" -ForegroundColor DarkGray
}

if ($snap2) {
    Write-Host "`n=== MENU APPEARED! gen=$($snap2.gen) ===" -ForegroundColor Green
    $snap2 | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_menu.json" -Encoding UTF8
    
    foreach ($c in $snap2.b.children) {
        Write-Host "Root: kind=$($c.kind) cls=$($c.cls) title=$($c.title) vis=$($c.vis)" -ForegroundColor Cyan
        if ($c.children) {
            foreach ($cc in $c.children) {
                $txt = if ($cc.text) { $cc.text } else { "" }
                Write-Host "  $txt kind=$($cc.kind) id=$($cc.id) r=$($cc.r -join ',')" -ForegroundColor Gray
                if ($cc.children) {
                    foreach ($ccc in $cc.children) {
                        $txt2 = if ($ccc.text) { $ccc.text } else { "" }
                        Write-Host "    $txt2 kind=$($ccc.kind) id=$($ccc.id) r=$($ccc.r -join ',')" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }
} else {
    Write-Host "No menu appeared" -ForegroundColor Red
}

$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
