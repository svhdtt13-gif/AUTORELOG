#TestStopVerify.ps1 - Verify stop command works
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
function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }

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
RecvOne | Out-Null
Send- '{"t":"launch","product_id":73}'
RecvOne | Out-Null

# Get current status of client_8 (khoqua10)
Write-Host "=== Current client status ===" -ForegroundColor Cyan
$msgs = RecvAll 3
$scrList = $null
foreach ($m in $msgs) { if ($m.t -eq "scr_list_res") { $scrList = $m } }
if ($scrList) {
    foreach ($inst in $scrList.instances) {
        if ($inst.id -like "*client_8*") {
            Write-Host "  client_8 (khoqua10): idx=$($inst.idx) state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "running") { "Green" } else { "Red" })
        }
    }
}

# Stop client_8 using instance_stop (the one that returned act_result)
Write-Host "`n=== Stopping client_8 (khoqua10) ===" -ForegroundColor Yellow
Send- '{"t":"instance_stop","id":"0:client_8"}'
Start-Sleep -Seconds 2

$allMsgs = RecvAll 5
Write-Host "Got $($allMsgs.Count) messages:" -ForegroundColor Gray
foreach ($m in $allMsgs) {
    if ($m.t -eq "act_result") {
        Write-Host "  ACT_RESULT: id=$($m.id) ok=$($m.ok) reason=$($m.reason)" -ForegroundColor Green
        $m | ConvertTo-Json | Write-Host -ForegroundColor Green
    } elseif ($m.t -eq "scr_list_res") {
        foreach ($inst in $m.instances) {
            if ($inst.id -like "*client_8*") {
                Write-Host "  client_8 now: state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "offline") { "Green" } else { "Yellow" })
            }
        }
    } else {
        Write-Host "  $($m.t)" -ForegroundColor DarkGray
    }
}

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
