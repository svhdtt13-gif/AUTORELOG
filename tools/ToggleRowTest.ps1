#ToggleRowTest.ps1 - full logging row_toggle on a given row; observe act_result + checked transition
param([Parameter(Mandatory=$true)][int]$Row)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152

function New-WS { $w = New-Object System.Net.WebSockets.ClientWebSocket; $w.Options.SetRequestHeader("Authorization", "Bearer $token"); $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20); $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token"); $w.ConnectAsync($uri, $ct).Wait(); $w }
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
function RowState($snap) { foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { $row = $n.rows | Where-Object { $_.r -eq $Row }; if ($row) { return "chk=$($row.chk) checked=$($row.checked)" } } }; return "" }

# 3 toggle attempts, checking state transitions and act_result
for ($att = 1; $att -le 3; $att++) {
    Write-Host "`n===== ATTEMPT $att : row_toggle r=$Row =====" -ForegroundColor Magenta
    $w = New-WS; Open-UI $w
    $s = Get-Snapshot $w 8
    if (-not $s) { Write-Host "  no snapshot"; $w.Dispose(); break }
    $epoch = $s.sepoch
    Write-Host "  BEFORE: $(RowState $s) (epoch=$epoch)" -ForegroundColor Cyan
    $id = Make-Id
    $msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":' + $Row + ',"id":"' + $id + '","epoch":' + $epoch + '}'
    Write-Host "  SEND: $msg"
    Send-WS $w $msg
    # gather replies for 4s
    $gotResult = $false
    foreach ($raw in (Drain $w 4)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}); $gotResult = $true }
        if ($p.t -eq "snapshot") { Write-Host "  AFTER(conn): $(RowState $p)" -ForegroundColor Cyan }
        if ($p.t -eq "delta") { Write-Host "  delta recv" -ForegroundColor DarkGray }
    }
    Write-Host "  state=$($w.State) hadResult=$gotResult" -ForegroundColor $(if($w.State -eq 'Open'){"Green"}else{"DarkGray"})
    $w.Dispose()
    Start-Sleep -Milliseconds 500
    # re-query state
    $w2 = New-WS; Open-UI $w2
    $s2 = Get-Snapshot $w2 8
    if ($s2) { Write-Host "  AFTER(reconnect): $(RowState $s2)" -ForegroundColor Cyan }
    $w2.Dispose()
    Start-Sleep -Seconds 6
}