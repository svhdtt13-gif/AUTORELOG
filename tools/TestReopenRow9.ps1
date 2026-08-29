#TestReopenRow9.ps1 - Reopen row 9 after close test, verify
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$script:token = $data.session
$script:appRoom = "e1c51deba15917ba"
$script:ct = [System.Threading.CancellationToken]::None
$script:buf = New-Object byte[] 1048576

function New-WS {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $script:token")
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$($script:appRoom)&session=$($script:token)")
    $ws.ConnectAsync($uri, $script:ct).Wait()
    return $ws
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $script:ct).Wait() }
function Receive-WS($ws, [int]$secs) {
    $buf = $script:buf; $timeout = [DateTime]::UtcNow.AddSeconds($secs); $msgs = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $script:ct)
                if ($r.AsyncWaitHandle.WaitOne(800)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $msgs += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $msgs
}
function Get-Epoch($ws) {
    Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
    Send-WS $ws '{"t":"launch","product_id":73}'
    foreach ($raw in (Receive-WS $ws 6)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { return $p.sepoch }
    }
    return 0
}
function Get-RowState($ws, [int]$row) {
    foreach ($raw in (Receive-WS $ws 6)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") {
            foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { return ($n.rows | Where-Object { $_.r -eq $row }).checked } }
        }
    }
    return $null
}
function Make-Id {
    $chars = "abcdefghijklmnopqrstuvwxyz0123456789"; $Ah = ""
    for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
    return "$Ah`:1"
}

# ============ PHASE C: REOPEN row 9 ============
Write-Host "`n########## PHASE C: REOPEN row 9 ##########" -ForegroundColor Magenta
$ws = New-WS
Write-Host "Connected: $($ws.State)"
$epoch = Get-Epoch $ws
Write-Host "epoch=$epoch row9 now=$(Get-RowState $ws 9)" -ForegroundColor Cyan

$id = Make-Id
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":9,"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "`n[reopen] SEND: $msg" -ForegroundColor Yellow
Send-WS $ws $msg
foreach ($raw in (Receive-WS $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
    else { Write-Host "  $($p.t)" -ForegroundColor Gray }
}
Write-Host "State after reopen: $($ws.State)" -ForegroundColor Cyan; $ws.Dispose()

# ============ PHASE D: VERIFY reopen ============
Write-Host "`n########## PHASE D: VERIFY row 9 ##########" -ForegroundColor Magenta
Start-Sleep -Seconds 8
$ws = New-WS
Write-Host "Connected: $($ws.State)"
Get-Epoch $ws | Out-Null
$row9 = Get-RowState $ws 9
Write-Host "row9 after reopen = $row9  $(if ($row9 -eq 1) { '[RUNNING OK]' } else { '[NOT RUNNING]' })" -ForegroundColor $(if ($row9 -eq 1) { "Green" } else { "Red" })
$ws.Dispose()