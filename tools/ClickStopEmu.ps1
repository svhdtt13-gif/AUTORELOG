#ClickStopEmu.ps1 - Click "Tắt giả lập" in the popup menu
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

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# Open list menu
Write-Host "Opening list_menu..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}'
Start-Sleep -Seconds 2

# Collect to find popup key
$buf = New-Object byte[] 1048576
$popupKey = $null
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                # Find popup
                function Find-PopupKey($node) {
                    if ($node.popup -eq $true -and $node.kind -eq "menu") {
                        return $node.key
                    }
                    if ($node.children) {
                        foreach ($c in $node.children) {
                            $result = Find-PopupKey $c
                            if ($result) { return $result }
                        }
                    }
                    return $null
                }
                $popupKey = Find-PopupKey $p.b
                if ($popupKey) { Write-Host "Found popup key: $popupKey" -ForegroundColor Green }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if (-not $popupKey) { Write-Host "No popup found!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

# Click "Tắt giả lập" - item index 7 in the menu
Write-Host "`nClicking 'Tắt giả lập' (index 7)..." -ForegroundColor Yellow
$stopMsg = @{ t = "act"; k = $popupKey; op = "menu_click"; path = @(7) } | ConvertTo-Json -Compress
Send- $stopMsg

# Collect response
Write-Host "Waiting for response..." -ForegroundColor Gray
$timeout2 = [DateTime]::UtcNow.AddSeconds(5)
$count = 0
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $count++
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "act_result") {
                    Write-Host "[$count] ACT_RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
                }
                elseif ($p.t -eq "snapshot") {
                    Write-Host "[$count] snapshot gen=$($p.gen)" -ForegroundColor Green
                    $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_stop.json" -Encoding UTF8
                }
                elseif ($p.t -eq "delta") {
                    # Check for log messages about stopping
                    if ($p.b -and $p.b.ops) {
                        foreach ($op in $p.b.ops) {
                            if ($op.lines) {
                                foreach ($line in $op.lines) {
                                    if ($line.t -match "tat|stop|dung|offline") {
                                        Write-Host "  LOG: $($line.t)" -ForegroundColor Yellow
                                    }
                                }
                            }
                        }
                    }
                    Write-Host "[$count] delta" -ForegroundColor DarkGray
                }
                elseif ($p.t -eq "scr_list_res") {
                    Write-Host "[$count] scr_list_res" -ForegroundColor Cyan
                    # Check if any client went offline
                    foreach ($inst in $p.instances) {
                        if ($inst.state -eq "offline" -and $inst.id -match "client_8") {
                            Write-Host "  CLIENT_8 (khoqua10) IS NOW OFFLINE!" -ForegroundColor Green
                        }
                    }
                }
                else { Write-Host "[$count] $($p.t)" -ForegroundColor Gray }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "`nTotal: $count msgs, state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
