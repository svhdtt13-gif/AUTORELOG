#InspectTree.ps1 - Print root, list node en/cls, row toggle structure
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

if (-not $snap) { Write-Host "No snapshot" -ForegroundColor Red; $ws.Dispose(); exit }
Write-Host "Snapshot gen=$($snap.gen) sepoch=$($snap.sepoch)" -ForegroundColor DarkGray
$b = $snap.b
Write-Host "`n=== ROOT node ===" -ForegroundColor Green
Write-Host "  key=$($b.key) kind=$($b.kind) en=$($b.en) vis=$($b.vis) cls=$($b.cls) title=$(($b.title -replace '[^\x20-\x7E]','.')) r=$($b.r)"

# recursive find node root/1000#0 or key contains '1000'
function Find-Nodes($node, $depth, $maxDepth, [ref]$results) {
    if ($depth -gt $maxDepth) { return }
    $k = if ($node.key) { $node.key } else { "" }
    $t = if ($node.text) { ($node.text -replace '[^\x20-\x7E]','.') } else { "" }
    if ($k) { $results.Value.Add(@{ key=$k; depth=$depth; kind=$node.kind; en=$node.en; text=$t }) }
    if ($node.children) {
        foreach ($c in $node.children) { Find-Nodes $c ($depth+1) $maxDepth $results }
    }
}
$results = New-Object System.Collections.ArrayList
Find-Nodes $b 0 4 ([ref]$results)

Write-Host "`n=== All nodes <= depth 4 (key / kind / en / text) ===" -ForegroundColor Green
foreach ($n in $results) { Write-Host ("  " * $n.depth) + "key=$($n.key) kind=$($n.kind) en=$($n.en) text=$($n.text)" }

Write-Host "`n=== Target: list node root/1000#0 detail ===" -ForegroundColor Green
$listNode = $results | Where-Object { $_.key -eq "root/1000#0" }
if ($listNode) {
    Write-Host "  FOUND: depth=$($listNode.depth) en=$($listNode.en)"
}
# Also dump any node containing 1000
foreach ($n in $results | Where-Object { $_.key -match '1000' }) { Write-Host "  match1000: $($n | ConvertTo-Json -Compress)" -ForegroundColor Cyan }

$ws.Dispose()