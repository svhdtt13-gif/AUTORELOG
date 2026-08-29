#TestScrStart.ps1 - Try to claim screen
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
function RecvAll($secs) {
    $all = @()
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
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
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvAll 1 | Out-Null
Send- '{"t":"launch","product_id":73}'
$initMsgs = RecvAll 3

$driverToken = $null
foreach ($m in $initMsgs) {
    if ($m.t -eq "scr_took") { $driverToken = $m.dt; Write-Host "INITIAL scr_took! dt=$driverToken" -ForegroundColor Green }
}

# Try various scr_start formats
Write-Host "`n=== scr_start claim=1 ===" -ForegroundColor Yellow
Send- '{"t":"scr_start","idx":0,"claim":1}'
$msgs = RecvAll 3
foreach ($m in $msgs) {
    if ($m.t -eq "scr_took") { $driverToken = $m.dt; Write-Host "scr_took! idx=$($m.idx) dt=$driverToken" -ForegroundColor Green }
    elseif ($m.t -eq "scr_driver") { Write-Host "scr_driver! idx=$($m.idx) who=$($m.who)" -ForegroundColor Cyan }
    else { Write-Host "$($m.t)" -ForegroundColor Gray }
}

if (-not $driverToken) {
    Write-Host "`n=== scr_start with vid ===" -ForegroundColor Yellow
    $vid = [guid]::NewGuid().ToString("N").Substring(0, 8)
    Send- "{`"t`":`"scr_start`",`"idx`":0,`"vid`":`"$vid`",`"claim`":1}"
    $msgs = RecvAll 3
    foreach ($m in $msgs) {
        if ($m.t -eq "scr_took") { $driverToken = $m.dt; Write-Host "scr_took! dt=$driverToken" -ForegroundColor Green }
        elseif ($m.t -eq "scr_driver") { Write-Host "scr_driver! who=$($m.who)" -ForegroundColor Cyan }
        else { Write-Host "$($m.t)" -ForegroundColor Gray }
    }
}

if (-not $driverToken) {
    Write-Host "`n=== scr_start with lgen ===" -ForegroundColor Yellow
    Send- '{"t":"scr_start","idx":0,"lgen":1,"claim":1}'
    $msgs = RecvAll 3
    foreach ($m in $msgs) {
        if ($m.t -eq "scr_took") { $driverToken = $m.dt; Write-Host "scr_took! dt=$driverToken" -ForegroundColor Green }
        elseif ($m.t -eq "scr_driver") { Write-Host "scr_driver! who=$($m.who)" -ForegroundColor Cyan }
        else { Write-Host "$($m.t)" -ForegroundColor Gray }
    }
}

if (-not $driverToken) {
    Write-Host "`n=== scr_start without claim ===" -ForegroundColor Yellow
    Send- '{"t":"scr_start","idx":0}'
    $msgs = RecvAll 3
    foreach ($m in $msgs) {
        if ($m.t -eq "scr_took") { $driverToken = $m.dt; Write-Host "scr_took! dt=$driverToken" -ForegroundColor Green }
        elseif ($m.t -eq "scr_driver") { Write-Host "scr_driver! who=$($m.who)" -ForegroundColor Cyan }
        else { Write-Host "$($m.t)" -ForegroundColor Gray }
    }
}

Write-Host "`n=== Final: driverToken=$driverToken ===" -ForegroundColor Cyan
$ws.Dispose()
