#ConfirmStop3.ps1 - Try with epoch/id/holds like JS does
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
$buf = New-Object byte[] 1048576

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# list_menu r=5
Write-Host "Triggering stop dialog..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}'
Start-Sleep -Seconds 2

# Drain
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) { $ms.Dispose() } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "Dialog should be open. Trying multiple click formats..." -ForegroundColor Yellow

# Format 1: Full fields with epoch/id
$actId1 = "a$(Get-Random)"
$m1 = @{ t="act"; k="popup/0/6#0"; op="click"; id=$actId1; epoch=30; holds=@() } | ConvertTo-Json -Compress
Write-Host "`n[1] $m1" -ForegroundColor Yellow
Send- $m1
Start-Sleep -Milliseconds 500
if ($ws.State -ne "Open") { Write-Host "ABORTED after [1]" -ForegroundColor Red; $ws.Dispose(); exit 1 }
# Quick drain
$ms = New-Object System.IO.MemoryStream; $more = $true
while ($more -and $ws.State -eq "Open") {
    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
}
if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "  -> $($p.t) ok=$($p.ok)" -ForegroundColor Cyan }
$ms.Dispose()

# Format 2: key instead of k, with epoch
$actId2 = "b$(Get-Random)"
$m2 = @{ t="act"; key="popup/0/6#0"; op="click"; id=$actId2; epoch=30 } | ConvertTo-Json -Compress
Write-Host "`n[2] $m2" -ForegroundColor Yellow
Send- $m2
Start-Sleep -Milliseconds 500
if ($ws.State -ne "Open") { Write-Host "ABORTED after [2]" -ForegroundColor Red; $ws.Dispose(); exit 1 }
$ms = New-Object System.IO.MemoryStream; $more = $true
while ($more -and $ws.State -eq "Open") {
    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
}
if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "  -> $($p.t) ok=$($p.ok)" -ForegroundColor Cyan }
$ms.Dispose()

# Format 3: close op
Write-Host "`n[3] close op on popup" -ForegroundColor Yellow
$m3 = @{ t="act"; k="popup/0"; op="close" } | ConvertTo-Json -Compress
Send- $m3
Start-Sleep -Milliseconds 500
if ($ws.State -ne "Open") { Write-Host "ABORTED after [3]" -ForegroundColor Red; $ws.Dispose(); exit 1 }
$ms = New-Object System.IO.MemoryStream; $more = $true
while ($more -and $ws.State -eq "Open") {
    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
}
if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "  -> $($p.t) ok=$($p.ok)" -ForegroundColor Cyan }
$ms.Dispose()

# Format 4: menu_click with path to button
Write-Host "`n[4] menu_click path=[0] on popup" -ForegroundColor Yellow
$m4 = @{ t="act"; k="popup/0"; op="menu_click"; path=@(0) } | ConvertTo-Json -Compress
Send- $m4
Start-Sleep -Milliseconds 500
if ($ws.State -ne "Open") { Write-Host "ABORTED after [4]" -ForegroundColor Red; $ws.Dispose(); exit 1 }
$ms = New-Object System.IO.MemoryStream; $more = $true
while ($more -and $ws.State -eq "Open") {
    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
}
if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "  -> $($p.t) ok=$($p.ok)" -ForegroundColor Cyan }
$ms.Dispose()

Write-Host "`nFinal state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
