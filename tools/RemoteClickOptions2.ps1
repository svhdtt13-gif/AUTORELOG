#RemoteClickOptions2.ps1 - Caps -> launch -> trigger snapshot -> click More choices
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

function RecvAll($seconds) {
    $buf = New-Object byte[] 1048576
    $msgs = @()
    $timeout = [DateTime]::UtcNow.AddSeconds($seconds)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream
            $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) { $msgs += $p }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $msgs
}

function SendClick($x, $y) {
    Send- (@{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true } | ConvertTo-Json -Compress)
    Start-Sleep -Milliseconds 80
    Send- (@{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false } | ConvertTo-Json -Compress)
}

function SendWheel($delta) {
    Send- (@{ t = "scr_input"; idx = 0; dt = "wheel"; delta = $delta } | ConvertTo-Json -Compress)
}

function GetSnapshot {
    $msgs = RecvAll 3
    foreach ($m in $msgs) {
        if ($m.t -eq "snapshot") { return $m }
    }
    return $null
}

# Step 1: Caps
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 500
$msgs0 = RecvAll 1
Write-Host "Caps: $($msgs0.Count) msgs" -ForegroundColor Green

# Step 2: Launch
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500
$msgs1 = RecvAll 1
Write-Host "Launch: $($msgs1.Count) msgs" -ForegroundColor Green

# Step 3: Trigger snapshot with dummy click at center of list
Write-Host "Triggering snapshot..." -ForegroundColor Yellow
SendClick 300 70
$snapshot = GetSnapshot
if (-not $snapshot) { $snapshot = GetSnapshot }

if (-not $snapshot) {
    Write-Host "No snapshot!" -ForegroundColor Red
    $ws.Dispose(); exit 1
}

Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find list
$list = $null
foreach ($child in $snapshot.b.children) {
    if ($child.kind -eq "list" -and $child.total -gt 10) { $list = $child; break }
}

if (-not $list) { Write-Host "No list!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

Write-Host "List: r=$($list.r -join ',') visFrom=$($list.visFrom) visCount=$($list.visCount)" -ForegroundColor Cyan

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

# Scroll if needed
$rowH = $list.r[3] / $list.visCount
if ($targetRow -lt $list.visFrom -or $targetRow -ge ($list.visFrom + $list.visCount)) {
    Write-Host "Scrolling to row $targetRow..." -ForegroundColor Yellow
    $listCX = $list.r[0] + ($list.r[2] / 2)
    $listCY = $list.r[1] + ($list.r[3] / 2)
    SendClick $listCX $listCY
    Start-Sleep -Milliseconds 300
    
    $diff = $targetRow - $list.visFrom
    $dir = if ($diff -lt 0) { 3 } else { -3 }
    $count = [Math]::Abs($diff) + 2
    for ($i = 0; $i -lt $count; $i++) { SendWheel $dir; Start-Sleep -Milliseconds 100 }
    
    Start-Sleep -Seconds 1
    $newSnap = GetSnapshot
    if ($newSnap) {
        $snapshot = $newSnap
        $list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1
        Write-Host "After scroll: visFrom=$($list.visFrom)" -ForegroundColor Gray
    }
}

# Click More choices (column 3)
$clickX = $list.r[0] + 19 + 120 + 105 + 13
$rowIdx = $targetRow - $list.visFrom
$clickY = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)

Write-Host "Click 'More' at ($clickX, $clickY)" -ForegroundColor Yellow
SendClick $clickX $clickY

# Wait for menu
Start-Sleep -Seconds 2
$snap2 = GetSnapshot
if ($snap2) {
    Write-Host "`nMenu snapshot gen=$($snap2.gen)" -ForegroundColor Green
    $snap2 | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_menu.json" -Encoding UTF8
    
    # Find popup/menu
    foreach ($c in $snap2.b.children) {
        Write-Host "Root child: kind=$($c.kind) id=$($c.id) cls=$($c.cls) title=$($c.title) vis=$($c.vis)" -ForegroundColor Gray
        if ($c.children) {
            foreach ($cc in $c.children) {
                $txt = if ($cc.text) { $cc.text } else { "" }
                Write-Host "  sub: kind=$($cc.kind) id=$($cc.id) text=$txt r=$($cc.r -join ',')" -ForegroundColor Gray
                if ($cc.children) {
                    foreach ($ccc in $cc.children) {
                        $txt2 = if ($ccc.text) { $ccc.text } else { "" }
                        Write-Host "    leaf: kind=$($ccc.kind) id=$($ccc.id) text=$txt2 r=$($ccc.r -join ',')" -ForegroundColor DarkGray
                    }
                }
            }
        }
    }
} else {
    Write-Host "No menu snapshot!" -ForegroundColor Red
}

$ws.Dispose()
Write-Host "Done!" -ForegroundColor Cyan
