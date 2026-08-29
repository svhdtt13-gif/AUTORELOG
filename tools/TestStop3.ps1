#TestStop3.ps1 - Minimal: caps -> launch -> stop -> collect all
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

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 500
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500

# Stop client_8 IMMEDIATELY
Write-Host "Sending stop..." -ForegroundColor Yellow
Send- '{"t":"instance_stop","id":"0:client_8"}'

# Now collect ALL messages for 8 seconds
$buf = New-Object byte[] 1048576
$timeout = [DateTime]::UtcNow.AddSeconds(8)
$count = 0
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $count++
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "act_result") {
                    Write-Host "[$count] ACT_RESULT!" -ForegroundColor Green
                    $p | ConvertTo-Json | Write-Host -ForegroundColor Green
                } elseif ($p.t -eq "scr_list_res") {
                    $running = ($p.instances | Where-Object { $_.state -eq "running" }).Count
                    $offline = ($p.instances | Where-Object { $_.state -eq "offline" }).Count
                    Write-Host "[$count] scr_list_res: running=$running offline=$offline" -ForegroundColor Cyan
                    $c8 = $p.instances | Where-Object { $_.id -eq "0:client_8" }
                    if ($c8) { Write-Host "  client_8: state=$($c8.state)" -ForegroundColor $(if ($c8.state -eq "offline") { "Green" } else { "Yellow" }) }
                } elseif ($p.t -eq "snapshot") {
                    Write-Host "[$count] snapshot gen=$($p.gen)" -ForegroundColor Gray
                } elseif ($p.t -eq "delta") {
                    Write-Host "[$count] delta" -ForegroundColor DarkGray
                } else {
                    Write-Host "[$count] $($p.t)" -ForegroundColor DarkGray
                }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "`nTotal: $count messages, state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
