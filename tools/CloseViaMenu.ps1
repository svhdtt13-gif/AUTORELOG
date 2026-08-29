#CloseViaMenu.ps1 - khoqua09 FULL CLOSE (ASCII-safe) - khoqua09
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

$script:popups = New-Object System.Collections.ArrayList
$script:allButtons = New-Object System.Collections.ArrayList
function Scan($node) {
    if ($node.popup -eq $true) { [void]$script:popups.Add($node) }
    if ($node.kind -eq "button" -and $node.text) { [void]$script:allButtons.Add($node) }
    if ($node.buttons) { foreach ($b in $node.buttons) { [void]$script:allButtons.Add($b) } }
    if ($node.children) { foreach ($c in $node.children) { Scan $c } }
}
function Get-Snapshot($ws, [int]$secs) {
    foreach ($raw in (Drain $ws $secs)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
    return $null
}
function Connect-and-Snap {
    $w = New-WS; Open-UI $w
    $s = Get-Snapshot $w 6
    return @{ ws = $w; snap = $s }
}

# pattern for "Co" (C + o-with-acute) built from char codes, ASCII-safe
$coPattern = "^C" + [char]0x00F3 + "$"

Write-Host "### Step 1: open row menu (list_menu r=$TARGET)" -ForegroundColor Magenta
$c1 = Connect-and-Snap
if (-not $c1.snap) { Write-Host "no snapshot"; $c1.ws.Dispose(); exit }
$epoch = $c1.snap.sepoch
Write-Host "  epoch=$epoch state=$($c1.ws.State)"
Send-WS $c1.ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $TARGET + '}')
Start-Sleep -Milliseconds 300
Write-Host "  state after list_menu: $($c1.ws.State)" -ForegroundColor $(if($c1.ws.State -eq "Open"){"Green"}else{"Red"})
$c1.ws.Dispose()

Write-Host "`n### Step 2: reconnect, find popup + item cmd=32773 (Tat gia lap)" -ForegroundColor Magenta
$popupKey = $null; $itemPos = $null; $snapNow = $null
for ($try = 1; $try -le 6 -and -not $popupKey; $try++) {
    Start-Sleep -Milliseconds 400
    $c = Connect-and-Snap
    if ($c.snap) {
        $script:popups.Clear(); $snapNow = $c.snap
        Scan $c.snap.b
        if ($script:popups.Count) {
            $scanned = @($script:popups | Where-Object { $_.kind -eq "menu" })
            if ($scanned.Count) {
                $pconf = $scanned[0]
                $popupKey = $pconf.key
                Write-Host "  popup: $($pconf.key) kind=$($pconf.kind)" -ForegroundColor Green
                foreach ($it in $pconf.items) { Write-Host ("    pos={0} cmd={1} t='{2}'" -f $it.pos,$it.cmd,$it.t) -ForegroundColor Cyan }
                $it2 = $pconf.items | Where-Object { $_.cmd -eq 32773 }
                if ($it2) { $itemPos = $it2.pos } 
            }
        } else { Write-Host "  try ${try}: no popup" -ForegroundColor DarkGray }
    } else { Write-Host "  try ${try}: no snapshot" -ForegroundColor DarkGray }
    $c.ws.Dispose()
}
if (-not $popupKey -or $null -eq $itemPos) { Write-Host "FAILED: popup or item not found" -ForegroundColor Red; exit }

Write-Host "`n### Step 3: click 'Tat gia lap' at path [$itemPos]" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $popupKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $snapNow.sepoch + '}'
Write-Host "  SEND: $msg"
$c3 = Connect-and-Snap
if ($c3.snap) {
    Send-WS $c3.ws $msg
    Start-Sleep -Milliseconds 600
    foreach ($raw in (Drain $c3.ws 3)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
    Write-Host "  state after menu_click: $($c3.ws.State)" -ForegroundColor $(if($c3.ws.State -eq "Open"){"Green"}else{"Red"})
}
$c3.ws.Dispose()

Write-Host "`n### Step 4: reconnect, find confirmation button matching 'Co'" -ForegroundColor Magenta
$coKey = $null; $msgSnap = $null
for ($try = 1; $try -le 6 -and -not $coKey; $try++) {
    Start-Sleep -Milliseconds 500
    $c = Connect-and-Snap
    if ($c.snap) {
        $script:popups.Clear(); $script:allButtons.Clear(); $msgSnap = $c.snap
        Scan $c.snap.b
        $script:allButtons | Where-Object { $_.text -match $coPattern } | ForEach-Object { if (-not $coKey) { $coKey = $_.key; Write-Host "  CO key=$($_.key) kind=$($_.kind) text='$($_.text)'" -ForegroundColor Green } }
        if ($script:popups.Count) { foreach ($mp in $script:popups) { Write-Host ("  popup: {0} kind={1}" -f $mp.key,$mp.kind) -ForegroundColor Cyan } }
        if (-not $coKey) { Write-Host "  try ${try}: no Co button" -ForegroundColor DarkGray }
    } else { Write-Host "  try ${try}: no snapshot" -ForegroundColor DarkGray }
    $c.ws.Dispose()
}
if (-not $coKey) { Write-Host "FAILED: no confirmation button" -ForegroundColor Red; exit }

Write-Host "`n### Step 5: click 'Co' confirm" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $coKey + '","op":"click","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
Write-Host "  SEND: $msg"
$c5 = Connect-and-Snap
if ($c5.snap) {
    Send-WS $c5.ws $msg
    Start-Sleep -Milliseconds 600
    foreach ($raw in (Drain $c5.ws 3)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
    Write-Host "  state after Co click: $($c5.ws.State)" -ForegroundColor $(if($c5.ws.State -eq "Open"){"Green"}else{"Red"})
}
$c5.ws.Dispose()

Write-Host "`n### Step 6: VERIFY (wait 25s)" -ForegroundColor Magenta
Start-Sleep -Seconds 25
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