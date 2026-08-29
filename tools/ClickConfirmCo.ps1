#ClickConfirmCo.ps1 - click Có = popup/0/6#0 (msgbox already open), verify close
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
$TARGET = 9

function New-WS {
    $w = New-Object System.Net.WebSockets.ClientWebSocket
    $w.Options.SetRequestHeader("Authorization", "Bearer $token")
    $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $w.ConnectAsync($uri, $ct).Wait(); $w
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs); $out = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(400)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Get-Snapshot($ws, [int]$secs) {
    foreach ($raw in (Drain $ws $secs)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
    return $null
}
function Connect-and-Snap { $w = New-WS; Open-UI $w; $s = Get-Snapshot $w 6; return @{ ws = $w; snap = $s } }

Write-Host "### Confirm msgbox still open, then click Co ###" -ForegroundColor Magenta
$c = Connect-and-Snap
if (-not $c.snap) { Write-Host "no snapshot"; exit }
$epoch = $c.snap.sepoch
Write-Host "  epoch=$epoch"
# verify msgbox present
$hasMsg = $false
foreach ($n in $c.snap.b.children) { if ($n.popup -eq $true -and $n.kind -eq "msgbox") { $hasMsg = $true } }
Write-Host "  msgbox open: $hasMsg" -ForegroundColor $(if($hasMsg){"Green"}else{"Yellow"})
if (-not $hasMsg) { Write-Host "Msgbox NOT open - run CloseViaMenu step 1-3 first" -ForegroundColor Red; exit }

$id = Make-Id
$msg = '{"t":"act","key":"popup/0/6#0","op":"click","id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "  SEND: $msg" -ForegroundColor Yellow
Send-WS $c.ws $msg
Start-Sleep -Milliseconds 800
foreach ($raw in (Drain $c.ws 4)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
Write-Host "  state after Co click: $($c.ws.State)" -ForegroundColor $(if($c.ws.State -eq "Open"){"Green"}else{"Red"})
$c.ws.Dispose()

Write-Host "`n### VERIFY (wait 30s) ###" -ForegroundColor Magenta
Start-Sleep -Seconds 30
Write-Host "--- Local qnyh (khoqua09 = client_7) ---" -ForegroundColor Cyan
$gone = $true
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'khoqua09|client_7' } | ForEach-Object { Write-Host "  STILL RUNNING PID=$($_.Id)  $($_.MainWindowTitle)" -ForegroundColor Red; $gone = $false }
if ($gone) { Write-Host "  khoqua09 qnyh process GONE" -ForegroundColor Green }
Write-Host "  total qnyh: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Gray

Write-Host "--- Remote scr_list ---" -ForegroundColor Cyan
$c6 = Connect-and-Snap
if ($c6.snap) {
    Send-WS $c6.ws '{"t":"scr_list"}'
    for ($n = 0; $n -lt 3 -and $c6.ws.State -eq "Open"; $n++) {
        foreach ($raw in (Drain $c6.ws 6)) {
            if ($c6.ws.State -ne "Open") { break }
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "scr_list_res") {
                $i = $p.instances | Where-Object { $_.idx -eq $TARGET }
                if ($i) { Write-Host "  idx$TARGET ($($i.id)) state=$($i.state)  $(if($i.state -eq 'running'){'STILL RUNNING'}else{'NOT RUNNING'})" -ForegroundColor $(if($i.state -eq 'running'){"Red"}else{"Green"}) }
                $run = @($p.instances | Where-Object { $_.state -eq 'running' })
                Write-Host "  total running: $($run.Count)/27" -ForegroundColor Gray
            }
        }
    }
}
$c6.ws.Dispose()