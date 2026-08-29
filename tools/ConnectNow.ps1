#ConnectNow.ps1 - Fresh connect, snapshot + instance status
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
$snap = $null
$inst = $null
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snap = $p }
            elseif ($p.t -eq "scr_list_res") { $inst = $p }
            elseif ($p.t -eq "delta") { }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}

Write-Host "`n=== CONNECTION OK ===" -ForegroundColor Green
if ($inst) {
    Write-Host "`n--- Instances (scr_list_res) ---" -ForegroundColor Cyan
    foreach ($i in $inst.instances) {
        $state = $i.state
        $color = if ($state -eq "running") { "Green" } else { "DarkGray" }
        Write-Host ("  idx {0,2}  {1,-12}  {2,-22}  {3}" -f $i.idx, $i.id, $i.name, $state) -ForegroundColor $color
    }
}
if ($snap) {
    Write-Host "`n--- List rows (chk = bot on/off) ---" -ForegroundColor Cyan
    foreach ($n in $snap.b.children) {
        if ($n.key -eq "root/1000#0") {
            foreach ($row in $n.rows) {
                $on = if ($row.checked -eq 1) { "ON " } else { "OFF" }
                Write-Host "  row $($row.r)  $on" -ForegroundColor $(if ($row.checked -eq 1) { "Green" } else { "DarkGray" })
            }
        }
    }
    Write-Host "`nSeat: seatsUsed=$($inst.seatsUsed) seatsMax=$($inst.seatsMax) quotaLeft=$($inst.quotaLeft)" -ForegroundColor Yellow
}
Write-Host "Final state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()