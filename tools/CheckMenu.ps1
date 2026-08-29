#CheckMenu.ps1 - Check if act triggered a menu/popup
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

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }

function RecvAll($secs) {
    $all = @()
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream
            $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $all += $p }; $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $all
}

# Caps + launch
$buf = New-Object byte[] 1048576
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvOne | Out-Null
Send- '{"t":"launch","product_id":73}'
RecvOne | Out-Null

# Act on row 5 (khoqua10) - which is a running client we want to test closing
Write-Host "Sending act on list a=0 i=5..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","a":0,"i":5}'
Start-Sleep -Seconds 2

$allMsgs = RecvAll 3
$snapshot = $null
foreach ($m in $allMsgs) {
    if ($m.t -eq "snapshot") { $snapshot = $m }
}

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

Write-Host "Snapshot gen=$($snapshot.gen)" -ForegroundColor Green

# Save for analysis
$snapshot | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_act.json" -Encoding UTF8

# Scan ALL children recursively for popups, menus, buttons, etc.
function Show-All($node, $depth) {
    $indent = "  " * $depth
    $kind = $node.kind
    $vis = $node.vis
    $en = $node.en
    $txt = $node.text
    $title = $node.title
    $id = $node.id
    $r = $node.r
    $cls = $node.cls
    $key = $node.key
    
    $label = "$kind"
    if ($id) { $label += " id=$id" }
    if ($key) { $label += " key=$key" }
    if ($txt) { $label += " text='$txt'" }
    if ($title) { $label += " title='$title'" }
    if ($cls) { $label += " cls=$cls" }
    if ($r) { $label += " r=$($r -join ',')" }
    if ($vis -eq $false) { $label += " [HIDDEN]" }
    if ($en -eq $false) { $label += " [DISABLED]" }
    
    $color = "Gray"
    if ($kind -eq "button") { $color = "Yellow" }
    if ($txt -and $txt -match "tat|dung|stop|close|x") { $color = "Red" }
    if ($title -and $title -match "tat|dung|stop|close|menu|popup") { $color = "Red" }
    if ($kind -eq "popup" -or $kind -eq "menu" -or $kind -eq "contextmenu") { $color = "Red" }
    if ($kind -eq "listitem") { $color = "Cyan" }
    
    Write-Host "$indent$label" -ForegroundColor $color
    
    if ($node.children) {
        foreach ($c in $node.children) { Show-All $c ($depth + 1) }
    }
}

Write-Host "`n=== FULL UI TREE ===" -ForegroundColor Cyan
Show-All $snapshot.b 0

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
