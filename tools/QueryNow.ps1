#QueryNow.ps1 - request scr_list + local process check
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

Write-Host "=== LOCAL PROCESSES ===" -ForegroundColor Cyan
$ags = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if ($ags) { Write-Host "  AutoGhostStory: PID=$($ags.Id) Title='$($ags.MainWindowTitle)'" -ForegroundColor Green } else { Write-Host "  AutoGhostStory: NOT RUNNING" -ForegroundColor Red }
$qnyh = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
Write-Host "  qnyh emulators: $($qnyh.Count) running" -ForegroundColor $(if ($qnyh) { "Green" } else { "Gray" })
foreach ($p in $qnyh) { Write-Host "    PID=$($p.Id)  Title='$($p.MainWindowTitle)'" -ForegroundColor DarkGray }

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "`nWS Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500
Send- '{"t":"scr_list"}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "scr_list_res") {
                Write-Host "`n=== INSTANCES (scr_list_res) ===" -ForegroundColor Cyan
                Write-Host "  seatsUsed=$($p.seatsUsed) seatsMax=$($p.seatsMax) quotaLeft=$($p.quotaLeft) idleSec=$($p.idleSec)"
                foreach ($i in $p.instances) {
                    $color = if ($i.state -eq "running") { "Green" } else { "DarkGray" }
                    Write-Host ("  idx {0,2}  {1,-12}  {2,-22}  {3,-9}  cap={4}" -f $i.idx, $i.id, $i.name, $i.state, $i.cap) -ForegroundColor $color
                }
            }
            elseif ($p.t -eq "snapshot") { }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}
Write-Host "State: $($ws.State)" -ForegroundColor DarkGray
$ws.Dispose()