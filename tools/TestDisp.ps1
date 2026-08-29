#TestDisp.ps1 - Try connecting with disp=web and disp=app, then row_toggle
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function Test-Disp($disp) {
    Write-Host "`n=== disp=$disp ===" -ForegroundColor Yellow
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token&disp=$disp")
    $ct = [System.Threading.CancellationToken]::None
    try { $ws.ConnectAsync($uri, $ct).Wait() } catch { Write-Host "Connect failed: $($_.Exception.InnerException.Message)" -ForegroundColor Red; return }
    Write-Host "Connected: $($ws.State)" -ForegroundColor Green
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    $buf = New-Object byte[] 1048576
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    Start-Sleep -Milliseconds 300
    Send- '{"t":"launch","product_id":73}'
    Start-Sleep -Milliseconds 500
    
    # Read snapshot to get epoch
    $epoch = 0
    $timeout = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Write-Host "  snapshot sepoch=$epoch" -ForegroundColor DarkGray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    
    # Try row_toggle
    $chars = "abcdefghijklmnopqrstuvwxyz0123456789"
    $Ah = ""; for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
    $msg = @{ t="act"; key="root/1000#0"; op="row_toggle"; r=0; id="$Ah`:1"; epoch=$epoch; holds=@(@{key="root/1000#0"; field="row:0:checked"}) } | ConvertTo-Json -Compress
    Write-Host "  Send: $msg" -ForegroundColor DarkGray
    Send- $msg
    
    $timeout2 = [DateTime]::UtcNow.AddSeconds(4)
    $got = $false
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") { Write-Host "  ACT_RESULT ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }); $got = $true }
                elseif ($p.t -eq "snapshot") { 
                    Write-Host "  snapshot gen=$($p.gen)" -ForegroundColor Green
                    if ($p.b.rows) { Write-Host "  Row0 checked=$($p.b.rows[0].checked)" -ForegroundColor Yellow }
                    $got = $true
                }
                else { Write-Host "  $($p.t)" -ForegroundColor Gray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    Write-Host "  state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    $ws.Dispose()
}

Test-Disp "web"
Test-Disp "app"

Write-Host "`nDone" -ForegroundColor Cyan