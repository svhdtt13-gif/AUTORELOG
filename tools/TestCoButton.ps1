#TestCoButton.ps1 - try variants to activate msgbox Co button; check ack + dismiss each time
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152

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

function Get-State([ref]$snapshot) {
    $ws = New-WS; Open-UI $ws
    $msgs = Drain $ws 6
    $snap = $null
    foreach ($raw in $msgs) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { $snap = $p } }
    $snapshot = $snap
    $m = $false; $sKey = $null
    if ($snap) {
        # check any popup in tree
        foreach ($n in $snap.b.children) { if ($n.popup -eq $true) { $m = $true; $sKey = $n.key } }
    }
    $ws.Dispose()
    return @{ msg = $m; key = $sKey; epoch = if($snap){$snap.sepoch}else{0} }
}

function Send-Act($msg, [string]$name) {
    Write-Host "`n### $name : $msg" -ForegroundColor Magenta
    $ws = New-WS; Open-UI $ws
    $first = Get-State ([ref]$null)
    $epoch = $first.epoch
    # replace epoch with fresh
    $final = $msg -replace '"epoch":[0-9]+', ('"epoch":' + $epoch)
    Write-Host "   (epoch fresh -> $final)" -ForegroundColor Gray
    Send-WS $ws $final
    Start-Sleep -Milliseconds 1200
    $acks = @()
    foreach ($raw in (Drain $ws 4)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { $acks += "ok=$($p.ok) reason=$($p.reason)" } }
    if ($acks.Count) { $acks | ForEach-Object { Write-Host "   ACK: $_" -ForegroundColor Yellow } } else { Write-Host "   ACK: (none)" -ForegroundColor DarkGray }
    Write-Host "   state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
    $ws.Dispose()
    Start-Sleep -Milliseconds 800
    $st2 = Get-State ([ref]$null)
    Write-Host "   msgbox open after: $($st2.msg)" -ForegroundColor $(if(-not $st2.msg){"Green"}else{"Red"})
    return $st2
}

$base = $null
$st = Get-State ([ref]$base)
Write-Host "Initial: msgbox=$($st.msg) epoch=$($st.epoch)"

$id = Make-Id
$variants = @(
    @{ n="click full with id/epoch"; m='{"t":"act","key":"popup/0/6#0","op":"click","id":"' + $id + '","epoch":1}' },
    @{ n="click k short"; m='{"t":"act","k":"popup/0/6#0","op":"click"}' },
    @{ n="toggle full"; m='{"t":"act","key":"popup/0/6#0","op":"toggle","id":"' + $id + '","epoch":1}' },
    @{ n="select full"; m='{"t":"act","key":"popup/0/6#0","op":"select","id":"' + $id + '","epoch":1}' },
    @{ n="check_item full"; m='{"t":"act","key":"popup/0/6#0","op":"check_item","id":"' + $id + '","epoch":1}' },
    @{ n="cell_click full"; m='{"t":"act","key":"popup/0/6#0","op":"cell_click","c":0,"id":"' + $id + '","epoch":1}' }
)

foreach ($v in $variants) {
    $r = Send-Act $v.m $v.n
    if (-not $r.msg) { Write-Host ">>> VARIANT WORKED: $($v.n) - msgbox dismissed!" -ForegroundColor Green; break }
}