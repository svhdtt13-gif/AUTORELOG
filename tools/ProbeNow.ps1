#ProbeNow.ps1 - full probe: any popup in tree (ALL kinds), rows chk, scr_list detail
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token"); $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None; $ws.ConnectAsync($uri, $ct).Wait()
function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 2097152
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
function DrainQS($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
        $ms.Dispose()
    }
    return $null
}
$snap = DrainQS $ws 12
if (-not $snap) { Write-Host "no snapshot"; exit }
Write-Host "epoch=$($snap.sepoch)"
Write-Host "--- ALL popups/msgbox/menu in tree ---" -ForegroundColor Magenta
function Walk($node, $d) {
    if ($node.popup -eq $true) {
        $kids = ($node.children | ForEach-Object { "$($_.key):$($_.kind)" }) -join ' '
        Write-Host ("  key={0} kind={1} title='{2}' children=[{3}]" -f $node.key, $node.kind, $node.title, $kids) -ForegroundColor Yellow
        if ($node.items) { foreach ($it in $node.items) { Write-Host ("      pos={0} cmd={1} t='{2}'" -f $it.pos,$it.cmd,$it.t) -ForegroundColor DarkGray } }
    }
    if ($node.children) { foreach ($c in $node.children) { Walk $c ($d+1) } }
}
Walk $snap.b 0
Write-Host "--- rows 0..26 (r, chk, checked) ---" -ForegroundColor Cyan
foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { foreach ($row in $n.rows) { Write-Host ("  r={0} chk={1} checked={2}" -f $row.r, $row.chk, $row.checked) } } }
Write-Host "--- scr_list ---" -ForegroundColor Cyan
Send- '{"t":"scr_list"}'
$t1 = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $t1 -and $ws.State -eq "Open") {
    $ms = New-Object System.IO.MemoryStream; $more = $true
    while ($more -and $ws.State -eq "Open") {
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
        if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
    }
    if ($ms.Length -gt 0) {
        $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "scr_list_res") { foreach ($i in $p.instances) { Write-Host ("  idx={0,-2} {1,-12} state={2,-8} cap={3}" -f $i.idx, $i.id, $i.state, $i.cap) } }
    }
    $ms.Dispose()
}
$ws.Dispose()