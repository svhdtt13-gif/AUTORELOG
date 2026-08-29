#SaveSnapshot.ps1 - Save full snapshot for analysis
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

$receiveBuf = New-Object byte[] 65536
$allMsgs = @()
$timeout = [DateTime]::UtcNow.AddSeconds(5)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(1000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                $allMsgs += $parsed
            } catch {}
        }
    } catch { break }
}

# Save full data
$allMsgs | ConvertTo-Json -Depth 15 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\remote_snapshot_full.json" -Encoding UTF8
Write-Host "Saved $($allMsgs.Count) messages" -ForegroundColor Green

# Show snapshot structure
$snapshot = $allMsgs | Where-Object { $_.t -eq "snapshot" } | Select-Object -First 1
if ($snapshot) {
    Write-Host "`nSnapshot root keys:" -ForegroundColor Cyan
    Write-Host "  gen: $($snapshot.gen)" -ForegroundColor Gray
    Write-Host "  b.key: $($snapshot.b.key)" -ForegroundColor Gray
    Write-Host "  b.title: $($snapshot.b.title)" -ForegroundColor Gray
    Write-Host "  b.r: $($snapshot.b.r)" -ForegroundColor Gray
    Write-Host "  children count: $($snapshot.b.children.Count)" -ForegroundColor Gray
    
    # Show each child
    $i = 0
    foreach ($child in $snapshot.b.children) {
        Write-Host "`n  Child[$i]: kind=$($child.kind) id=$($child.id) key=$($child.key)" -ForegroundColor Yellow
        if ($child.items) {
            Write-Host "    items count: $($child.items.Count)" -ForegroundColor Gray
            # Show first item structure
            if ($child.items.Count -gt 0) {
                $first = $child.items[0]
                Write-Host "    first item keys: $($first.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
                Write-Host "    first item: $($first | ConvertTo-Json -Compress)" -ForegroundColor Gray
            }
        }
        if ($child.children) {
            Write-Host "    children count: $($child.children.Count)" -ForegroundColor Gray
            $j = 0
            foreach ($sub in $child.children) {
                Write-Host "    sub[$j]: kind=$($sub.kind) id=$($sub.id) title=$($sub.title)" -ForegroundColor DarkYellow
                if ($sub.items) {
                    Write-Host "      items count: $($sub.items.Count)" -ForegroundColor Gray
                    if ($sub.items.Count -gt 0) {
                        $firstItem = $sub.items[0]
                        Write-Host "      first item: $($firstItem | ConvertTo-Json -Compress)" -ForegroundColor Gray
                    }
                }
                if ($sub.children) {
                    Write-Host "      children count: $($sub.children.Count)" -ForegroundColor Gray
                }
                $j++
            }
        }
        $i++
    }
}

$ws.Dispose()
