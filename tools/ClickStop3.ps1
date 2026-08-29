#ClickStop3.ps1 - Full act message with id, epoch
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

function Send-($m) { Write-Host ">> $m" -ForegroundColor DarkGray; $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# List menu
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}'
Start-Sleep -Seconds 2

$buf = New-Object byte[] 1048576
$popupKey = $null
$sepoch = 0
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                $sepoch = $p.sepoch
                function Find-PK($node) { if ($node.popup -eq $true -and $node.kind -eq "menu") { return $node.key }; if ($node.children) { foreach ($c in $node.children) { $r = Find-PK $c; if ($r) { return $r } } }; return $null }
                $popupKey = Find-PK $p.b
                if ($popupKey) { Write-Host "Popup: $popupKey sepoch=$sepoch" -ForegroundColor Green }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if (-not $popupKey) { Write-Host "No popup!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

# Try menu_click with ALL fields
$actId = "mcl_$(Get-Random)"
$clickMsg = @{
    t = "act"
    k = $popupKey
    op = "menu_click"
    path = @(7)
    id = $actId
    epoch = $sepoch
} | ConvertTo-Json -Compress

Write-Host "`nClicking stop..." -ForegroundColor Yellow
Send- $clickMsg

$timeout2 = [DateTime]::UtcNow.AddSeconds(5)
$count = 0
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $count++
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") { Write-Host "[$count] RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
            elseif ($p.t -eq "snapshot") { Write-Host "[$count] snapshot" -ForegroundColor Green }
            elseif ($p.t -eq "scr_list_res") { Write-Host "[$count] scr_list_res" -ForegroundColor Cyan }
            else { Write-Host "[$count] $($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "state=$($ws.State) msgs=$count" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
