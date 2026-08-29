#TestStopClient.ps1 - Try stopping individual client via WebSocket
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function DoTest($msg, $label) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    RecvOne | Out-Null
    Send- '{"t":"launch","product_id":73}'
    RecvOne | Out-Null
    
    Write-Host "`n$label" -ForegroundColor Yellow
    Write-Host "  Send: $msg" -ForegroundColor DarkGray
    
    try {
        Send- $msg
        Start-Sleep -Milliseconds 500
        $timeout = [DateTime]::UtcNow.AddSeconds(3)
        while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
            try {
                $buf = New-Object byte[] 1048576
                $ms = New-Object System.IO.MemoryStream
                $more = $true
                while ($more -and $ws.State -eq "Open") {
                    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
                }
                if ($ms.Length -gt 0) {
                    $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($p) {
                        if ($p.t -eq "snapshot") { Write-Host "  -> snapshot OK" -ForegroundColor Green }
                        elseif ($p.t -eq "delta") { Write-Host "  -> delta OK" -ForegroundColor Green }
                        elseif ($p.t -eq "scr_list_res") { Write-Host "  -> scr_list_res OK" -ForegroundColor Green }
                        else { Write-Host "  -> $($p.t) $($p.PSObject.Properties.Name -join ',')" -ForegroundColor Gray }
                    }
                    $ms.Dispose()
                } else { $ms.Dispose(); break }
            } catch { break }
        }
        Write-Host "  State: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    } catch {
        Write-Host "  -> ERROR" -ForegroundColor Red
    }
    
    $ws.Dispose()
}

# Try various stop-like commands
DoTest '{"t":"stop","product_id":73}' "stop product_id=73"
DoTest '{"t":"stop","product_id":73,"force":false}' "stop product_id=73 force=false"
DoTest '{"t":"stop","idx":5}' "stop idx=5 (khoqua10)"
DoTest '{"t":"stop","instance":"0:client_8"}' "stop instance=client_8"
DoTest '{"t":"stop","id":"0:client_8"}' "stop id=client_8"
DoTest '{"t":"scr_stop","idx":5}' "scr_stop idx=5"
DoTest '{"t":"scr_close","idx":5}' "scr_close idx=5"
DoTest '{"t":"instance_stop","idx":5}' "instance_stop idx=5"
DoTest '{"t":"instance_stop","id":"0:client_8"}' "instance_stop id=client_8"

Write-Host "`nDone!" -ForegroundColor Cyan
