#RemoteSession.ps1 - Persistent WebSocket session for Auto Ghost Story control
param(
    [string]$Action = "list",  # list, launch, stop, click
    [int]$ClientIdx = -1       # client index to act on
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

# Create WebSocket
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")

$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()

# Send caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Receive snapshot
$receiveBuf = New-Object byte[] 131072
$snapshot = $null
$scrList = $null
$timeout = [DateTime]::UtcNow.AddSeconds(5)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(1000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") { $snapshot = $parsed }
                if ($parsed.t -eq "scr_list_res") { $scrList = $parsed }
            } catch {}
        }
    } catch { break }
}

if ($Action -eq "list") {
    # Show running clients
    Write-Host "=== RUNNING CLIENTS ===" -ForegroundColor Cyan
    if ($scrList -and $scrList.instances) {
        foreach ($inst in $scrList.instances) {
            $status = if ($inst.state -eq "running") { "[ON]" } else { "[OFF]" }
            Write-Host "  $status idx=$($inst.idx) id=$($inst.id) name=$($inst.name)" -ForegroundColor $(if($inst.state -eq "running"){"Green"}else{"Red"})
        }
        Write-Host "Total: $($scrList.instances.Count)" -ForegroundColor White
    }
    
    # Show client list from snapshot
    if ($snapshot -and $snapshot.b) {
        Write-Host "`n=== CLIENT LIST ===" -ForegroundColor Cyan
        $root = $snapshot.b
        if ($root.children) {
            foreach ($child in $root.children) {
                if ($child.kind -eq "list" -and $child.total) {
                    Write-Host "List: total=$($child.total) checked=$($child.checked)" -ForegroundColor Gray
                    # Show first few items
                    if ($child.items) {
                        $i = 0
                        foreach ($item in $child.items) {
                            if ($i -lt 30) {
                                $name = if ($item.c -and $item.c.Count -gt 1) { $item.c[1] } else { "?" }
                                $chk = if ($item.checked -eq 1) { "[X]" } else { "[ ]" }
                                $status = if ($item.c -and $item.c.Count -gt 2) { $item.c[2] } else { "?" }
                                Write-Host "  $chk r=$($item.r) name=$name status=$status" -ForegroundColor Gray
                            }
                            $i++
                        }
                    }
                }
            }
        }
    }
}

if ($Action -eq "launch") {
    Write-Host "=== LAUNCH PRODUCT 73 ===" -ForegroundColor Yellow
    $launch = @{ t = "launch"; product_id = 73 } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($launch)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Write-Host "Sent: $launch" -ForegroundColor Gray
    Start-Sleep -Seconds 3
}

if ($Action -eq "stop") {
    Write-Host "=== STOP PRODUCT 73 ===" -ForegroundColor Yellow
    $stop = @{ t = "stop"; product_id = 73; force = $false } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($stop)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Write-Host "Sent: $stop" -ForegroundColor Gray
    Start-Sleep -Seconds 3
}

if ($Action -eq "click" -and $ClientIdx -ge 0) {
    Write-Host "=== CLICK CLIENT IDX $ClientIdx ===" -ForegroundColor Yellow
    
    # Find the client in snapshot and get its coordinates
    if ($snapshot -and $snapshot.b) {
        $root = $snapshot.b
        if ($root.children) {
            foreach ($child in $root.children) {
                if ($child.kind -eq "list" -and $child.items) {
                    $i = 0
                    foreach ($item in $child.items) {
                        if ($i -eq $ClientIdx) {
                            $r = $item.r  # [x, y, w, h]
                            if ($r -and $r.Count -ge 4) {
                                $clickX = $r[0] + 10  # checkbox at left
                                $clickY = $r[1] + ($r[3] / 2)  # center vertically
                                
                                Write-Host "Clicking at ($clickX, $clickY) on client $i" -ForegroundColor Gray
                                
                                # Send mouse input
                                $mouseDown = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = $clickX; y = $clickY; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
                                $mouseUp = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = $clickX; y = $clickY; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
                                
                                $buf1 = [System.Text.Encoding]::UTF8.GetBytes($mouseDown)
                                $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf1)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
                                Start-Sleep -Milliseconds 50
                                $buf2 = [System.Text.Encoding]::UTF8.GetBytes($mouseUp)
                                $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf2)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
                                
                                Write-Host "Clicked!" -ForegroundColor Green
                            }
                            break
                        }
                        $i++
                    }
                }
            }
        }
    }
}

# Cleanup
if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
}
$ws.Dispose()
