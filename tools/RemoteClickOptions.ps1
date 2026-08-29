#RemoteClickOptions.ps1 - Connect, launch, scroll to client, click More choices
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
                $msgs += $p
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $msgs
}

function SendClick($x, $y) {
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true } | ConvertTo-Json -Compress
    Send- $d
    Start-Sleep -Milliseconds 80
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false } | ConvertTo-Json -Compress
    Send- $u
}

function SendWheel($delta) {
    $w = @{ t = "scr_input"; idx = 0; dt = "wheel"; delta = $delta } | ConvertTo-Json -Compress
    Send- $w
}

# Connect + handshake
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvAll 2

Send- '{"t":"launch","product_id":73}'
$msgs = RecvAll 3

# Find snapshot
$snapshot = $null
foreach ($m in $msgs) {
    if ($m.t -eq "snapshot") { $snapshot = $m }
}

if (-not $snapshot) {
    # Try receiving more
    $msgs2 = RecvAll 3
    foreach ($m in $msgs2) {
        if ($m.t -eq "snapshot") { $snapshot = $m }
    }
}

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Find list
$list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1
Write-Host "List: r=$($list.r -join ',') visFrom=$($list.visFrom) visCount=$($list.visCount) total=$($list.total)" -ForegroundColor Cyan

# Find target
$targetRow = -1
foreach ($item in $list.rows) {
    if ($item.c.Count -gt 1) {
        $name = $item.c[1].Trim()
        if ($name -like "*$ClientName*" -or $ClientName -like "*$name*") {
            $targetRow = $item.r
            Write-Host "Found: $name at row $targetRow (checked=$($item.checked))" -ForegroundColor Green
            break
        }
    }
}

if ($targetRow -lt 0) {
    Write-Host "Not found: $ClientName" -ForegroundColor Red
    Write-Host "Available:" -ForegroundColor Yellow
    foreach ($item in $list.rows) {
        if ($item.c.Count -gt 1) {
            $st = if ($item.checked -eq 1) { "[ON]" } else { "[OFF]" }
            Write-Host "  $st row=$($item.r) $($item.c[1])" -ForegroundColor Gray
        }
    }
    $ws.Dispose(); exit 1
}

# Calculate click position
$rowH = $list.r[3] / $list.visCount
$col3X = 19 + 120 + 105  # column 3 start
$col3W = 26
$clickX = $list.r[0] + $col3X + ($col3W / 2)

# Scroll if needed
if ($targetRow -lt $list.visFrom -or $targetRow -ge ($list.visFrom + $list.visCount)) {
    Write-Host "Row $targetRow not visible (visFrom=$list.visFrom), scrolling..." -ForegroundColor Yellow
    
    # Click list to focus
    $listCX = $list.r[0] + ($list.r[2] / 2)
    $listCY = $list.r[1] + ($list.r[3] / 2)
    SendClick $listCX $listCY
    Start-Sleep -Milliseconds 300
    
    # Scroll up/down
    $scrollDir = if ($targetRow -lt $list.visFrom) { 3 } else { -3 }
    $scrollCount = [Math]::Abs($targetRow - $list.visFrom) + 2
    
    for ($i = 0; $i -lt $scrollCount; $i++) {
        SendWheel $scrollDir
        Start-Sleep -Milliseconds 100
    }
    
    Start-Sleep -Seconds 1
    $msgs3 = RecvAll 2
    foreach ($m in $msgs3) {
        if ($m.t -eq "snapshot") { $snapshot = $m; $list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1 }
    }
    Write-Host "After scroll: visFrom=$($list.visFrom)" -ForegroundColor Gray
}

# Click More choices
$rowIdx = $targetRow - $list.visFrom
$clickY = $list.r[1] + ($rowIdx * $rowH) + ($rowH / 2)

Write-Host "Click 'More' at ($clickX, $clickY) for row $targetRow" -ForegroundColor Yellow
SendClick $clickX $clickY

# Wait for menu to appear
Start-Sleep -Seconds 2
$msgs4 = RecvAll 3
$snapshot2 = $null
foreach ($m in $msgs4) {
    if ($m.t -eq "snapshot") { $snapshot2 = $m }
}

if ($snapshot2) {
    Write-Host "`nNew snapshot gen=$($snapshot2.gen)" -ForegroundColor Green
    $snapshot2 | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_menu.json" -Encoding UTF8
    
    # Look for popup/menu
    if ($snapshot2.b.children) {
        foreach ($c in $snapshot2.b.children) {
            $kind = $c.kind
            $title = $c.title
            $text = $c.text
            Write-Host "  child: kind=$kind title=$title text=$text id=$($c.id)" -ForegroundColor Gray
            if ($c.children) {
                foreach ($cc in $c.children) {
                    Write-Host "    sub: kind=$($cc.kind) id=$($cc.id) text=$($cc.text) r=$($cc.r -join ',')" -ForegroundColor Gray
                    if ($cc.children) {
                        foreach ($ccc in $cc.children) {
                            Write-Host "      leaf: kind=$($ccc.kind) id=$($ccc.id) text=$($ccc.text)" -ForegroundColor DarkGray
                        }
                    }
                }
            }
        }
    }
} else {
    Write-Host "No new snapshot - menu may not have appeared" -ForegroundColor Red
}

Write-Host "`nDone!" -ForegroundColor Cyan
$ws.Dispose()
