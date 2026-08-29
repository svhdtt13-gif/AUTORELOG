#CheckStatus.ps1 - Get live client status from remote
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

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# Get snapshot
Send- '{"t":"act","k":"root/1000#0","a":0}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
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
                # Find all rows with client info
                function Show-Rows($node) {
                    if ($node.children) {
                        foreach ($c in $node.children) {
                            if ($c.text -and $c.text -match "client_") {
                                $st = if ($c.st) { $c.st } else { "?" }
                                $vis = if ($c.vis -eq $false) { " [HIDDEN]" } else { "" }
                                Write-Host "  $($c.text) st=$st$vis" -ForegroundColor $(if ($st -eq "offline") { "Red" } elseif ($st -eq "running" -or $st -eq "online") { "Green" } else { "Yellow" })
                            }
                            Show-Rows $c
                        }
                    }
                    # Also check text content
                    if ($node.t -and $node.t -match "client_") {
                        $st = if ($node.st) { $node.st } else { "?" }
                        Write-Host "  $($node.t) st=$st" -ForegroundColor Gray
                    }
                }
                Write-Host "=== ALL CLIENTS IN SNAPSHOT ===" -ForegroundColor Cyan
                Show-Rows $p.b
                
                # Also show st values
                Write-Host "`n=== CHECKING st VALUES ===" -ForegroundColor Cyan
                function Show-ST($node, $path) {
                    if ($node.st) {
                        $txt = if ($node.text) { $node.text } else { "" }
                        $key = if ($node.key) { $node.key } else { "" }
                        Write-Host "  $path st=$($node.st) '$txt' key=$key" -ForegroundColor Gray
                    }
                    if ($node.children) { $idx=0; foreach ($c in $node.children) { Show-ST $c "$path/$idx"; $idx++ } }
                }
                Show-ST $p.b "root"
                
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_live.json" -Encoding UTF8
                Write-Host "`nSaved to snapshot_live.json" -ForegroundColor Green
            }
            elseif ($p.t -eq "scr_list_res") {
                Write-Host "`n=== scr_list_res ===" -ForegroundColor Cyan
                foreach ($inst in $p.instances) {
                    $color = switch ($inst.state) { "online" { "Green" } "offline" { "Red" } default { "Yellow" } }
                    Write-Host "  $($inst.id) $($inst.name) state=$($inst.state)" -ForegroundColor $color
                }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

$ws.Dispose()
