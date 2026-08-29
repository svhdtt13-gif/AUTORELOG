#InspectList.ps1 - Dump rows inside root/1000#0 with chk/checked/r
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

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$snap = $null
$timeout = [DateTime]::UtcNow.AddSeconds(6)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open" -and -not $snap) {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snap = $p }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}
$ws.Dispose()
if (-not $snap) { Write-Host "No snapshot"; exit }

function Find-ByKey($node, $targetKey) {
    if ($node.key -eq $targetKey) { return $node }
    if ($node.children) { foreach ($c in $node.children) { $res = Find-ByKey $c $targetKey; if ($res) { return $res } } }
    return $null
}
$list = Find-ByKey $snap.b "root/1000#0"
Write-Host "list en=$($list.en) cls=$($list.cls)" -ForegroundColor Green
Write-Host "row data:" -ForegroundColor Green
foreach ($row in $list.rows) {
    $txt = ($row.text -replace '[^\x20-\x7E]','.')
    Write-Host "  r=$($row.r) chk=$($row.chk) checked=$($row.checked) en=$($row.en) text='$txt'" -ForegroundColor Cyan
}
$snap | ConvertTo-Json -Depth 10 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_full.json" -Encoding UTF8
Write-Host "`nSaved snapshot_full.json ($((Get-Item 'C:\Users\ADMIN\Documents\ai tool\tools\snapshot_full.json').Length) bytes)" -ForegroundColor DarkGray