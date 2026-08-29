#GetSnapshot.ps1 - Get full snapshot with large buffer
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

$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Use large buffer and accumulate messages
$receiveBuf = New-Object byte[] 1048576  # 1MB
$snapshot = $null
$timeout = [DateTime]::UtcNow.AddSeconds(8)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(2000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") {
                    $snapshot = $parsed
                    $snapshot | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot.json" -Encoding UTF8
                    Write-Host "Snapshot saved! gen=$($parsed.gen)" -ForegroundColor Green
                }
            } catch {}
        }
    } catch { break }
}

$ws.Dispose()

if ($snapshot) {
    Write-Host "Snapshot root: $($snapshot.b.key) title=$($snapshot.b.title)" -ForegroundColor Cyan
    
    # Find list items
    function Find-Lists($node, $depth) {
        if ($node.kind -eq "list" -and $node.items) {
            Write-Host ("  {0}List: id={1} total={2} items={3}" -f ("  " * $depth), $node.id, $node.total, $node.items.Count) -ForegroundColor Yellow
            if ($node.items.Count -gt 0) {
                $item = $node.items[0]
                Write-Host ("  {0}First item r={1} chk={2}" -f ("  " * $depth), ($item.r -join ","), $item.chk) -ForegroundColor Gray
                if ($item.act) {
                    Write-Host ("  {0}Actions: $($item.act | ConvertTo-Json -Compress)" -f ("  " * $depth)) -ForegroundColor Gray
                }
                if ($item.c) {
                    Write-Host ("  {0}Columns: $($item.c -join ' | ')" -f ("  " * $depth)) -ForegroundColor Gray
                }
            }
        }
        if ($node.children) {
            foreach ($child in $node.children) {
                Find-Lists $child ($depth + 1)
            }
        }
    }
    
    Find-Lists $snapshot.b 0
} else {
    Write-Host "No snapshot received" -ForegroundColor Red
}
