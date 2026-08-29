#DumpMsgbox.ps1 - connect, find msgbox, dump full node
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

$timeout = [DateTime]::UtcNow.AddSeconds(8)
$foundMsg = $false
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                function Walk($node, $d) {
                    if ($node.popup -eq $true) {
                        Write-Host "=== POPUP node (depth $d) ===" -ForegroundColor Magenta
                        $node | ConvertTo-Json -Depth 15
                    }
                    if ($node.children) { foreach ($c in $node.children) { Walk $c ($d+1) } }
                }
                Walk $p.b 0
                $foundMsg = $true
                $ws.Dispose(); break
            }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}
if (-not $foundMsg) { Write-Host "no snapshot / no msgbox" -ForegroundColor Red; $ws.Dispose() }