#DebugLive.ps1 - isolate Get-LiveRunning logic, dump raw scr_list messages
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token"); $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None; $ws.ConnectAsync($uri, $ct).Wait(); Write-Host "Connected: $($ws.State)"
function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 2097152
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

# drain snapshot
$gotSnap = $false
$t0 = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $t0 -and $ws.State -eq "Open" -and -not $gotSnap) {
    $ms = New-Object System.IO.MemoryStream; $more = $true
    while ($more -and $ws.State -eq "Open") {
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
        if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        if ($ms.Length -gt 10000000) { break }
    }
    if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "recv: $($p.t)"; if ($p.t -eq "snapshot") { $gotSnap = $true } }
    $ms.Dispose()
}
Write-Host "snapshot: $gotSnap  state: $($ws.State)"

Send- '{"t":"scr_list"}'
Write-Host "sent scr_list"
$t1 = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $t1 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
            if ($ms.Length -gt 10000000) { break }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "scr_list_res") {
                Write-Host "scr_list_res instances=$($p.instances.Count)"
                foreach ($i in $p.instances) { Write-Host "  idx=$($i.idx) state=$($i.state) id=$($i.id)" }
                $gotList = $true
            } else { Write-Host "recv: $($p.t)" }
        }
    } catch { break }
    $ms.Dispose()
}
$ws.Dispose()