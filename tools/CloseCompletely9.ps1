#CloseCompletely9.ps1 - FULL CLOSE khoqua09: list_menu r=9 -> confirm -> verify
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 1048576
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
                if ($r.AsyncWaitHandle.WaitOne(350)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $out += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $out
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }

# Recursively find nodes that look like menu/dialog/button; match text keywords
$hits = New-Object System.Collections.ArrayList
function Find-UI($node, $depth) {
    $txt = ($node.text -replace '\s+',' ')
    $isUI = ($node.key -match 'popup|menu|dialog|msgbox|btn|button|stat') -or ($node.kind -match 'menu|dialog|message|button')
    $isMatch = $txt -match 'tắt|giả lập|chắc chắn|Có|Không|Đồng' -or $txt -match 'tat|gia lap|chac chan|Co |Khong'
    if ($isUI -or $isMatch) {
        [void]$hits.Add([PSCustomObject]@{ key=$node.key; kind=$node.kind; text=$txt; depth=$depth; en=$node.en })
    }
    if ($node.children) { foreach ($c in $node.children) { Find-UI $c ($depth+1) } }
}
$epoch = 0
$lastSnap = $null
function On-Msg($p, [string]$tag) {
    if ($p.t -eq "snapshot") { $script:epoch = $p.sepoch; $script:lastSnap = $p; Write-Host "  [$tag] SNAPSHOT gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor DarkGray }
    elseif ($p.t -eq "delta") { Write-Host "  [$tag] delta" -ForegroundColor DarkGray }
    elseif ($p.t -eq "act_result") { Write-Host "  [$tag] act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
    Write-Host "  [$tag] $($p.t)" -ForegroundColor DarkGray
}

Write-Host "### STEP 0: connect + snapshot ###" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
foreach ($raw in (Drain $ws 5)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { $epoch = $p.sepoch; $lastSnap = $p } }
foreach ($n in $lastSnap.b.children) { if ($n.key -eq "root/1000#0") { $c = ($n.rows | Where-Object {$_.r -eq $TARGET}).checked; Write-Host "  row $TARGET chk=$c  $(if($c -eq 1){'ON'}else{'OFF'})" -ForegroundColor $(if($c -eq 1){"Green"}else{"Red"}) } }
Write-Host "  epoch=$epoch state=$($ws.State)" -ForegroundColor Cyan

Write-Host "`n### STEP 1: list_menu r=$TARGET ###" -ForegroundColor Magenta
Send-WS $ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $TARGET + '}')
# capture all messages, scan recursively
for ($n = 0; $n -lt 3; $n++) {
    foreach ($raw in (Drain $ws 2)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot" -or $p.t -eq "delta") {
            $hits.Clear()
            if ($p.b) { Find-UI $p.b 1 }
            foreach ($h in $hits) { Write-Host ("    [UI] {0}{1} kind={2} en={3} text='{4}'" -f (' ' * $h.depth), $h.key, $h.kind, $h.en, $h.text) -ForegroundColor Yellow }
            if ($p.t -eq "snapshot") { $epoch = $p.sepoch }
        }
        elseif ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
    }
    if ($ws.State -ne "Open") { break }
    Start-Sleep -Milliseconds 300
}
Write-Host "  state after list_menu: $($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
$ws.Dispose()

Write-Host "`n### STEP 2: reconnect + find open dialog ###" -ForegroundColor Magenta
Start-Sleep -Milliseconds 400
$ws = New-WS; Open-UI $ws
$dialog = $null
foreach ($raw in (Drain $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") {
        $hits.Clear(); Find-UI $p.b 1
        foreach ($h in $hits) { Write-Host ("    [UI] {0}{1} kind={2} en={3} text='{4}'" -f (' ' * $h.depth), $h.key, $h.kind, $h.en, $h.text) -ForegroundColor Yellow }
        # find the confirm button (text contains Co) inside popup key
        foreach ($h in $hits) { if ($h.key -match 'popup' -and $h.kind -eq 'button' -and $h.text -match 'Co') { $dialog = $h; } }
    }
}
if ($dialog) {
    Write-Host "  FOUND confirm button: key=$($dialog.key) text='$($dialog.text)'" -ForegroundColor Green
    $id = Make-Id
    $msg = '{"t":"act","key":"' + $dialog.key + '","op":"click","id":"' + $id + '","epoch":' + $epoch + '}'
    Write-Host "`n### STEP 3: click '$($dialog.text)' -> SEND: $msg" -ForegroundColor Magenta
    Send-WS $ws $msg
    for ($n = 0; $n -lt 3; $n++) {
        foreach ($raw in (Drain $ws 2)) {
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
        }
        if ($ws.State -ne "Open") { break }
        Start-Sleep -Milliseconds 300
    }
    Write-Host "  state after click: $($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
} else {
    Write-Host "  NO confirm dialog found" -ForegroundColor Red
}
$ws.Dispose()

Write-Host "`n### STEP 4: VERIFY (wait 15s) ###" -ForegroundColor Magenta
Start-Sleep -Seconds 15
Write-Host "--- Local: qnyh processes (khoqua09 = client_7) ---" -ForegroundColor Cyan
$qnyh = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
$found = $qnyh | Where-Object { $_.MainWindowTitle -match 'khoqua09|client_7' }
if ($found) { foreach ($p in $found) { Write-Host "  STILL RUNNING PID=$($p.Id)  $($p.MainWindowTitle)" -ForegroundColor Red } } else { Write-Host "  khoqua09 process GONE" -ForegroundColor Green }
Write-Host "  total qnyh: $($qnyh.Count)" -ForegroundColor Gray

Write-Host "--- Remote: instance status ---" -ForegroundColor Cyan
$ws = New-WS; Open-UI $ws
Start-Sleep -Milliseconds 400
Send-WS $ws '{"t":"scr_list"}'
foreach ($raw in (Drain $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { $c = ($n.rows | Where-Object {$_.r -eq $TARGET}).checked; Write-Host "  row $TARGET chk=$c $(if($c -eq 1){'ON'}else{'OFF'})" -ForegroundColor $(if($c -eq 1){"Green"}else{"Red"}) } } }
    if ($p.t -eq "scr_list_res") {
        $i = $p.instances | Where-Object { $_.idx -eq $TARGET }
        Write-Host "  idx$TARGET ($($i.id)) state=$($i.state)  $(if($i.state -eq 'running'){'STILL RUNNING'}else{'CLOSED (instance gone/offline)'})" -ForegroundColor $(if($i.state -eq 'running'){"Red"}else{"Green"})
        $running = @($p.instances | Where-Object { $_.state -eq 'running' })
        Write-Host "  total instances running: $($running.Count)" -ForegroundColor Gray
    }
}
$ws.Dispose()