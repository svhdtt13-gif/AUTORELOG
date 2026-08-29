#DiagScrTest.ps1 - minimal: connect, snapshot, scr_list, print every frame
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None; $buf = New-Object byte[] 2097152
$w = New-Object System.Net.WebSockets.ClientWebSocket
$w.Options.SetRequestHeader("Authorization", "Bearer $token"); $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$w.ConnectAsync($uri, $ct).Wait()
function SW($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $w.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
SW '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
SW '{"t":"launch","product_id":73}'
Write-Host "state after launch: $($w.State)"
$t0 = [DateTime]::UtcNow.AddSeconds(12)
while ([DateTime]::UtcNow -lt $t0 -and $w.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $w.State -eq "Open") {
            $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(500)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) {
            $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { Write-Host "snapshot recv sepoch=$($p.sepoch) state=$($w.State)" ; break } else { Write-Host "pre-scr got: $($p.t)" }
        }
        $ms.Dispose()
    } catch { Write-Host "EXC: $($_.Exception.Message)"; break }
}
Write-Host "after snapshot loop, state=$($w.State)  (sleeping 1s before scr_list)"
Start-Sleep -Seconds 1
SW '{"t":"scr_list"}'
$t1 = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $t1 -and $w.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $w.State -eq "Open") {
            $r = $w.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(500)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) {
            $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            Write-Host "recv: $($p.t)  state=$($w.State)"
            if ($p.t -eq "scr_list_res") { Write-Host "  instances: $($p.instances.Count)" }
        }
        $ms.Dispose()
    } catch { Write-Host "EXC2: $($_.Exception.Message)"; break }
}
Write-Host "done, state=$($w.State)"
$w.Dispose()