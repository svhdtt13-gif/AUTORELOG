#ConfirmStop.ps1 - Click "Có" (Yes) button to confirm stopping emulator
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
function RecvAll($secs) {
    $all = @()
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $all += $p }; $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $all
}

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# list_menu r=5 to trigger stop confirmation
Write-Host "Opening stop dialog for row 5 (khoqua10)..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}'
Start-Sleep -Seconds 2

# Find msgbox and button keys
$buf = New-Object byte[] 1048576
$yesKey = $null
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
                function Find-Buttons($node) {
                    if ($node.popup -eq $true -and $node.kind -eq "msgbox") {
                        Write-Host "MSGBOX found: key=$($node.key)" -ForegroundColor Green
                        if ($node.children) {
                            foreach ($c in $node.children) {
                                $txt = if ($c.text) { $c.text } else { "" }
                                Write-Host "  $($c.kind) '$txt' key=$($c.key)" -ForegroundColor Cyan
                                if ($txt -match "C|Yes|OK|confirm") {
                                    $script:yesKey = $c.key
                                    Write-Host "  -> THIS IS THE YES BUTTON!" -ForegroundColor Green
                                }
                            }
                        }
                    }
                    if ($node.children) { foreach ($c in $node.children) { Find-Buttons $c } }
                }
                Find-Buttons $p.b
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if (-not $yesKey) {
    Write-Host "No yes button found! Trying default key popup/0/6#0" -ForegroundColor Yellow
    $yesKey = "popup/0/6#0"
}

# Click "Có" (Yes) button
Write-Host "`nClicking 'Có' (Yes) to confirm stop..." -ForegroundColor Yellow
$clickMsg = @{ t = "act"; k = $yesKey; op = "click" } | ConvertTo-Json -Compress
Write-Host "Send: $clickMsg" -ForegroundColor DarkGray
Send- $clickMsg

# Wait for response
Write-Host "Waiting..." -ForegroundColor Gray
$timeout2 = [DateTime]::UtcNow.AddSeconds(8)
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
            if ($p.t -eq "act_result") {
                Write-Host "[$count] RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
            }
            elseif ($p.t -eq "scr_list_res") {
                foreach ($inst in $p.instances) {
                    if ($inst.id -eq "0:client_8") {
                        Write-Host "[$count] CLIENT_8: $($inst.name) state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "offline") { "Green" } else { "Yellow" })
                    }
                }
            }
            elseif ($p.t -eq "snapshot") {
                Write-Host "[$count] snapshot gen=$($p.gen)" -ForegroundColor Green
            }
            elseif ($p.t -eq "delta") {
                if ($p.b -and $p.b.ops) {
                    foreach ($op in $p.b.ops) {
                        if ($op.lines) {
                            foreach ($line in $op.lines) {
                                Write-Host "  LOG: $($line.t)" -ForegroundColor Yellow
                            }
                        }
                    }
                }
                Write-Host "[$count] delta" -ForegroundColor DarkGray
            }
            else { Write-Host "[$count] $($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "`nTotal: $count msgs, state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
