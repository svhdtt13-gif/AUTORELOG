#TestCorrectFormat.ps1 - Use correct WebSocket protocol
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

# Collect all messages for N seconds
$global:allMsgs = @()
function RecvAll($secs) {
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) { $global:allMsgs += $p }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
}

# Step 1: Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvAll 1
Send- '{"t":"launch","product_id":73}'
RecvAll 3

Write-Host "=== Messages received ===" -ForegroundColor Cyan
foreach ($m in $global:allMsgs) {
    if ($m.t -eq "scr_took") { Write-Host "SCR_TOOK! idx=$($m.idx) dt=$($m.dt)" -ForegroundColor Green }
    elseif ($m.t -eq "scr_driver") { Write-Host "SCR_DRIVER! idx=$($m.idx) who=$($m.who)" -ForegroundColor Green }
    elseif ($m.t -eq "snapshot") { Write-Host "snapshot gen=$($m.gen)" -ForegroundColor Gray }
    else { Write-Host "$($m.t)" -ForegroundColor DarkGray }
}

# Step 2: Try to claim screen 0
Write-Host "`n=== Claim screen 0 ===" -ForegroundColor Yellow
Send- '{"t":"scr_start","idx":0,"claim":1}'
$global:allMsgs = @()
RecvAll 3

$driverToken = $null
foreach ($m in $global:allMsgs) {
    if ($m.t -eq "scr_took") {
        $driverToken = $m.dt
        Write-Host "GOT DRIVER TOKEN: $driverToken" -ForegroundColor Green
    }
    elseif ($m.t -eq "scr_driver") {
        Write-Host "DRIVER: idx=$($m.idx) who=$($m.who)" -ForegroundColor Cyan
    }
    else { Write-Host "$($m.t)" -ForegroundColor DarkGray }
}

if (-not $driverToken) {
    Write-Host "No driver token! Trying without claim..." -ForegroundColor Red
}

# Step 3: Try act with list_menu (the correct format from JS analysis)
Write-Host "`n=== Try list_menu on list ===" -ForegroundColor Yellow
$actId = "test_$(Get-Random)"
$actMsg = @{ t = "act"; key = "root/1000#0"; op = "list_menu"; r = 5; id = $actId; epoch = 0 } | ConvertTo-Json -Compress
Write-Host "Send: $actMsg" -ForegroundColor DarkGray
Send- $actMsg
$global:allMsgs = @()
RecvAll 3

foreach ($m in $global:allMsgs) {
    if ($m.t -eq "act_result") {
        Write-Host "ACT_RESULT: ok=$($m.ok) reason=$($m.reason)" -ForegroundColor $(if ($m.ok) { "Green" } else { "Red" })
    }
    elseif ($m.t -eq "snapshot") {
        Write-Host "snapshot gen=$($m.gen)" -ForegroundColor Green
        # Check for popup/menu nodes
        if ($m.b.children) {
            foreach ($c in $m.b.children) {
                if ($c.kind -eq "menu" -or $c.kind -eq "popup" -or $c.popup -eq $true) {
                    Write-Host "  MENU/POPUP FOUND! kind=$($c.kind) id=$($c.id) vis=$($c.vis)" -ForegroundColor Red
                    if ($c.children) {
                        foreach ($cc in $c.children) {
                            $txt = if ($cc.text) { $cc.text } else { "" }
                            Write-Host "    item: $($cc.kind) '$txt' id=$($cc.id)" -ForegroundColor Red
                        }
                    }
                }
            }
        }
    }
    else { Write-Host "$($m.t)" -ForegroundColor DarkGray }
}

# Step 4: Also try act with op=click on control 11 (More choices)
Write-Host "`n=== Try click on More choices control ===" -ForegroundColor Yellow
$actId2 = "test_$(Get-Random)"
$actMsg2 = @{ t = "act"; key = "root/1000#0"; op = "click"; id = $actId2; epoch = 0 } | ConvertTo-Json -Compress
Write-Host "Send: $actMsg2" -ForegroundColor DarkGray
Send- $actMsg2
$global:allMsgs = @()
RecvAll 3

foreach ($m in $global:allMsgs) {
    if ($m.t -eq "act_result") {
        Write-Host "ACT_RESULT: ok=$($m.ok) reason=$($m.reason)" -ForegroundColor $(if ($m.ok) { "Green" } else { "Red" })
    }
    elseif ($m.t -eq "snapshot") {
        Write-Host "snapshot gen=$($m.gen)" -ForegroundColor Green
        $m | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_click.json" -Encoding UTF8
    }
    else { Write-Host "$($m.t)" -ForegroundColor DarkGray }
}

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
