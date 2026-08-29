#TestStop2.ps1 - Try both formats that returned act_result
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function TryStop($stopMsg, $clientId, $label) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }
    
    # Caps + launch
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    RecvOne | Out-Null
    Send- '{"t":"launch","product_id":73}'
    RecvOne | Out-Null
    
    # Check current state
    $buf = New-Object byte[] 1048576
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
                if ($p.t -eq "scr_list_res") {
                    foreach ($inst in $p.instances) {
                        if ($inst.id -eq $clientId) {
                            Write-Host "$label - Before: $($inst.name) state=$($inst.state)" -ForegroundColor Cyan
                        }
                    }
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    
    # Send stop
    Write-Host "$label - Sending: $stopMsg" -ForegroundColor Yellow
    Send- $stopMsg
    Start-Sleep -Seconds 3
    
    # Receive response
    $timeout2 = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) {
                    if ($p.t -eq "act_result") {
                        Write-Host "$label - ACT_RESULT: id=$($p.id) ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Green
                    } elseif ($p.t -eq "scr_list_res") {
                        foreach ($inst in $p.instances) {
                            if ($inst.id -eq $clientId) {
                                Write-Host "$label - After: $($inst.name) state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "offline") { "Green" } else { "Yellow" })
                            }
                        }
                    } elseif ($p.t -eq "snapshot") {
                        Write-Host "$label - snapshot gen=$($p.gen)" -ForegroundColor Gray
                    } else {
                        Write-Host "$label - $($p.t)" -ForegroundColor DarkGray
                    }
                }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    
    Write-Host "$label - Final state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    $ws.Dispose()
}

# Test both formats on client_8 (khoqua10)
TryStop '{"t":"stop","id":"0:client_8"}' "0:client_8" "stop+id"
TryStop '{"t":"instance_stop","id":"0:client_8"}' "0:client_8" "instance_stop+id"

Write-Host "`nDone!" -ForegroundColor Cyan
