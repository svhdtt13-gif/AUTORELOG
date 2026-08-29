#OpenClient14_v4.ps1 - Try various commands to open client_14
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
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

function Drain-Result {
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
                if ($p.t -eq "act_result") { Write-Host "  RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }); $ms.Dispose(); return $p }
                elseif ($p.t -eq "snapshot") { Write-Host "  snapshot gen=$($p.gen)" -ForegroundColor Green; $ms.Dispose(); return $p }
                else { Write-Host "  $($p.t)" -ForegroundColor DarkGray; $ms.Dispose() }
            } else { $ms.Dispose(); return $null }
        } catch { return $null }
    }
    return $null
}

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300
Start-Sleep -Seconds 1

# Try various approaches
Write-Host "`n=== [1] instance_start client_14 ===" -ForegroundColor Yellow
Send- '{"t":"instance_start","id":"0:client_14"}'
Drain-Result | Out-Null

Write-Host "`n=== [2] start instance_id 0:client_14 ===" -ForegroundColor Yellow
Send- '{"t":"start","instance_id":"0:client_14"}'
Drain-Result | Out-Null

Write-Host "`n=== [3] act toggle with row index ===" -ForegroundColor Yellow
Send- '{"t":"act","key":"root/1000#0","op":"toggle","id":"t1","epoch":33,"r":0,"col":0}'
Drain-Result | Out-Null

Write-Host "`n=== [4] act click with row+col ===" -ForegroundColor Yellow
Send- '{"t":"act","key":"root/1000#0","op":"click","id":"c1","epoch":33,"r":0,"col":0}'
Drain-Result | Out-Null

Write-Host "`n=== [5] scr_start claim for client_14 ===" -ForegroundColor Yellow
Send- '{"t":"scr_start","idx":"0:client_14","vid":"0:client_14","lgen":0,"claim":1}'
Drain-Result | Out-Null

Write-Host "`n=== [6] set_text with check=1 ===" -ForegroundColor Yellow
Send- '{"t":"act","key":"root/1000#0","op":"set_text","id":"s1","epoch":33,"r":0,"col":0,"text":"1"}'
Drain-Result | Out-Null

Write-Host "`n=== [7] scr_cmd check ===" -ForegroundColor Yellow
Send- '{"t":"scr_cmd","cmd":"check","idx":"0:client_14"}'
Drain-Result | Out-Null

Write-Host "`nFinal state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
