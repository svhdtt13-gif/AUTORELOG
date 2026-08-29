#GetSnapshot2.ps1 - Collect all messages with larger timeout
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
Write-Host "Connected" -ForegroundColor Green

$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

$receiveBuf = New-Object byte[] 1048576
$allData = ""
$timeout = [DateTime]::UtcNow.AddSeconds(10)
$msgCount = 0

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $ms = New-Object System.IO.MemoryStream
        $more = $true
        while ($more -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
            $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($result.AsyncWaitHandle.WaitOne(1000)) {
                $ms.Write($receiveBuf, 0, $result.Result.Count)
                $more = -not $result.Result.EndOfMessage
            } else {
                $more = $false
            }
        }
        if ($ms.Length -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $msgCount++
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") {
                    Write-Host "SNAPSHOT! gen=$($parsed.gen) size=$($msg.Length)" -ForegroundColor Green
                    $msg | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot.json" -Encoding UTF8
                    
                    # Show list structure
                    if ($parsed.b -and $parsed.b.children) {
                        foreach ($child in $parsed.b.children) {
                            if ($child.kind -eq "list" -and $child.items) {
                                Write-Host "  List id=$($child.id) total=$($child.total) items=$($child.items.Count)" -ForegroundColor Yellow
                                if ($child.items.Count -gt 0) {
                                    $item = $child.items[0]
                                    Write-Host "  First: r=$($item.r) chk=$($item.chk)" -ForegroundColor Gray
                                    if ($item.act) { Write-Host "  Actions: $($item.act | ConvertTo-Json -Compress)" -ForegroundColor Gray }
                                    if ($item.c) { Write-Host "  Cols: $($item.c -join ' | ')" -ForegroundColor Gray }
                                }
                            }
                        }
                    }
                } elseif ($parsed.t -eq "delta") {
                    Write-Host "Delta seq=$($parsed.seq)" -ForegroundColor DarkGray
                } else {
                    Write-Host "MSG[$msgCount]: $($parsed.t)" -ForegroundColor Gray
                }
            } catch {
                Write-Host "Parse error on msg $msgCount" -ForegroundColor Red
            }
        }
        $ms.Dispose()
    } catch {
        Write-Host "Error: $_" -ForegroundColor Red
        break
    }
}

Write-Host "Total: $msgCount messages, state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
