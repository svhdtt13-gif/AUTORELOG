#TestActRow.ps1 - Test act message with row targeting
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function DoTest($actMsg, $label) {
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
    
    Write-Host "`n$label" -ForegroundColor Yellow
    Write-Host "  Sending: $actMsg" -ForegroundColor DarkGray
    
    try {
        Send- $actMsg
        Start-Sleep -Milliseconds 500
        
        $buf = New-Object byte[] 1048576
        $got = @()
        $timeout = [DateTime]::UtcNow.AddSeconds(3)
        while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
            try {
                $ms = New-Object System.IO.MemoryStream
                $more = $true
                while ($more -and $ws.State -eq "Open") {
                    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
                }
                if ($ms.Length -gt 0) {
                    $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($p) { $got += $p }
                    $ms.Dispose()
                } else { $ms.Dispose(); break }
            } catch { break }
        }
        
        foreach ($m in $got) {
            if ($m.t -eq "snapshot") {
                Write-Host "  -> snapshot gen=$($m.gen) OK" -ForegroundColor Green
            } elseif ($m.t -eq "delta") {
                Write-Host "  -> delta OK" -ForegroundColor Green
            } else {
                Write-Host "  -> $($m.t)" -ForegroundColor Gray
            }
        }
        Write-Host "  state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    } catch {
        Write-Host "  -> ERROR: $($_.Exception.InnerException.Message)" -ForegroundColor Red
    }
    
    $ws.Dispose()
}

# Test: act with row index in different positions
DoTest '{"t":"act","k":"root/1000#0","a":0}' "No row - just act on list"
DoTest '{"t":"act","k":"root/1000#0","a":0,"i":0}' "i:0 (row 0)"
DoTest '{"t":"act","k":"root/1000#0","a":0,"i":5}' "i:5 (row 5 = khoqua10)"
DoTest '{"t":"act","k":"root/1000#0","a":0,"r":0}' "r:0 (row 0)"
DoTest '{"t":"act","k":"root/1000#0","a":0,"r":5}' "r:5 (row 5)"
DoTest '{"t":"act","k":"root/1000#0","a":0,"at":0}' "at:0 (row 0)"
DoTest '{"t":"act","k":"root/1000#0","a":0,"at":5}' "at:5 (row 5)"

Write-Host "`nDone!" -ForegroundColor Cyan
