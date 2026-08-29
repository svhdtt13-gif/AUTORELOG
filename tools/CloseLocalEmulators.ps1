#CloseLocalEmulators.ps1 - FULL CLOSE emulators by killing local qnyh processes (= Tat gia lap), then verify remote
# Usage: powershell -File CloseLocalEmulators.ps1 -Rows 6,9
param([Parameter(Mandatory=$true)][string]$Rows)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$db = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\client_database.json" -Raw | ConvertFrom-Json
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152

$idxList = @($Rows -split ',' | ForEach-Object { [int]$_.Trim() })

# map idx -> clientId
$idMap = @{}
foreach ($c in $db.clients) { $idMap[[int]$c.idx] = $c.client }

function Get-QnyhByClient($cid) {
    return @(Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match [regex]::Escape($cid) })
}

Write-Host "=== CLOSE local emulators ===" -ForegroundColor Magenta
foreach ($idx in $idxList) {
    $cid = $idMap[$idx]
    Write-Host "`n--- idx $idx ($cid) ---" -ForegroundColor Cyan
    $procs = Get-QnyhByClient $cid
    if (-not $procs.Count) { Write-Host "  no qnyh process found for $cid (already closed?)" -ForegroundColor DarkGray; continue }
    foreach ($p in $procs) {
        Write-Host "  closing PID=$($p.Id)  $($p.MainWindowTitle)" -ForegroundColor Yellow
        try { $null = $p.CloseMainWindow(); Write-Host "    CloseMainWindow sent" -ForegroundColor Gray } catch { Write-Host "    CloseMainWindow failed: $($_.Exception.Message)" -ForegroundColor Red }
    }
    # wait for graceful close
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while ([DateTime]::UtcNow -lt $deadline) {
        $alive = Get-QnyhByClient $cid
        if (-not $alive.Count) { break }
        Start-Sleep -Milliseconds 800
    }
    $alive = Get-QnyhByClient $cid
    if ($alive.Count) {
        Write-Host "  still alive after 20s - force kill" -ForegroundColor Red
        foreach ($p in $alive) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 3
        $alive = Get-QnyhByClient $cid
        if ($alive.Count) { Write-Host "  STILL ALIVE - FAILED to kill" -ForegroundColor Red } else { Write-Host "  force-killed (process gone)" -ForegroundColor Green }
    } else {
        Write-Host "  process GONE (emulator window fully closed)" -ForegroundColor Green
    }
}
Write-Host "`nlocal qnyh count now: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Gray

Write-Host "`n=== VERIFY remote scr_list ===" -ForegroundColor Magenta
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token"); $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ws.ConnectAsync($uri, $ct).Wait()
function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send- '{"t":"launch","product_id":73}'
function DrainQ($secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
        $ms.Dispose()
    }
    return $null
}
DrainQ 8 | Out-Null
Start-Sleep -Milliseconds 200
Send- '{"t":"scr_list"}'
$t1 = [DateTime]::UtcNow.AddSeconds(10)
while ([DateTime]::UtcNow -lt $t1 -and $ws.State -eq "Open") {
    $ms = New-Object System.IO.MemoryStream; $more = $true
    while ($more -and $ws.State -eq "Open") {
        $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
        if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
    }
    if ($ms.Length -gt 0) {
        $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "scr_list_res") {
            foreach ($idx in $idxList) {
                $i = $p.instances | Where-Object { $_.idx -eq $idx }
                if ($i) { Write-Host "  idx$idx ($($i.id)) state=$($i.state)  $(if($i.state -eq 'running'){'STILL RUNNING'}else{'CLOSED'})" -ForegroundColor $(if($i.state -eq 'running'){"Red"}else{"Green"}) }
            }
            $run = @($p.instances | Where-Object { $_.state -eq 'running' })
            Write-Host "  total running: $($run.Count)/27" -ForegroundColor Gray
        }
    }
    $ms.Dispose()
}
$ws.Dispose()