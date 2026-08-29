#CheckStateNow.ps1 - current state: msgbox open? rows? scr_list?
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 2097152

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 400

$timeout = [DateTime]::UtcNow.AddSeconds(8)
$snap = $null
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snap = $p; break }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}
if ($snap) {
    Write-Host "epoch=$($snap.sepoch)"
    Write-Host "--- popups/msgbox in tree ---" -ForegroundColor Cyan
    function Walk($node, $d) {
        if ($node.popup -eq $true) { Write-Host ("  popup key={0} kind={1} text='{2}'" -f $node.key, $node.kind, $node.text) -ForegroundColor Magenta }
        if ($node.children) { foreach ($c in $node.children) { Walk $c ($d+1) } }
    }
    Walk $snap.b 0
}

Start-Sleep -Milliseconds 300
Send- '{"t":"scr_list"}'
$timeout = [DateTime]::UtcNow.AddSeconds(8)
$listDone = $false
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open" -and -not $listDone) {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "scr_list_res") {
                Write-Host "--- scr_list_res: running instances ---" -ForegroundColor Cyan
                foreach ($i in ($p.instances | Where-Object { $_.state -eq 'running' })) { Write-Host "  idx$($i.idx) $($i.id) $($i.name)" -ForegroundColor Green }
                $i9 = $p.instances | Where-Object { $_.idx -eq 9 }
                Write-Host "  idx9 state=$($i9.state)" -ForegroundColor $(if($i9.state -eq 'running'){"Red"}else{"Green"})
                $listDone = $true
            }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}
$ws.Dispose()
Write-Host "--- local qnyh count: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Cyan
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'khoqua09|client_7' } | ForEach-Object { Write-Host "  khoqua09 PID=$($_.Id) STILL RUNNING" -ForegroundColor Red }