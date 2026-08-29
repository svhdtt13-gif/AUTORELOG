#CloseEmulator2.ps1 - robust FULL CLOSE: list_menu -> fast-capture popup OR direct menu_click popup/0 -> msgbox -> toggle Co -> verify
param([Parameter(Mandatory=$true)][int]$Row)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
$TARGET = $Row

function New-WS { $w = New-Object System.Net.WebSockets.ClientWebSocket; $w.Options.SetRequestHeader("Authorization", "Bearer $token"); $w.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20); $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token"); $w.ConnectAsync($uri, $ct).Wait(); $w }
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs); $out = @(); $dropped = $false
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
    if ($ws.State -ne "Open") { $dropped = $true }
    return @{ ok = -not $dropped; msgs = $out }
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Snap($ws) { $r = Drain $ws 6; foreach ($m in $r.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return @{ snap = $p; ok = $r.ok } } }; return @{ snap = $null; ok = $r.ok } }
function Find-AnyPopup($node) { $r = @(); if ($node.popup -eq $true) { $r += $node }; if ($node.children) { foreach ($c in $node.children) { $r += Find-AnyPopup $c } }; return $r }

Write-Host "### Closing row $TARGET (list_menu) ###" -ForegroundColor Magenta
# Step 1: open the row context menu
$w = New-WS; Open-UI $w; $s0 = Snap $w
if ($s0.snap) { Write-Host "  epoch=$($s0.snap.sepoch)" }
Send-WS $w ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $TARGET + '}')
$d = Drain $w 1
Write-Host "  list_menu -> conn ok=$($d.ok) msgs=$($d.msgs.Count)" -ForegroundColor $(if($d.ok){"Green"}else{"Yellow"})
# if still open, keep alive a moment then dispose
Start-Sleep -Milliseconds 150
$aborted = ($w.State -ne "Open")
$w.Dispose()

$menuKey = $null; $itemPos = $null; $usedEpoch = $null
if ($aborted) {
    Write-Host "  connection aborted => popup likely opened, will use direct popup/0 key" -ForegroundColor Yellow
}
# Fast reconnect loop to capture popup if it persisted
for ($try = 1; $try -le 6 -and -not $menuKey; $try++) {
    Start-Sleep -Milliseconds 180
    $w = New-WS; Open-UI $w
    $s = Snap $w
    if ($s.snap) {
        $usedEpoch = $s.snap.sepoch
        $pops = Find-AnyPopup $s.snap.b
        foreach ($p in $pops) {
            if ($p.key -eq "popup/0" -and $p.kind -eq "menu") {
                $it = $p.items | Where-Object { $_.cmd -eq 32773 }
                if ($it) { $menuKey = $p.key; $itemPos = $it.pos; Write-Host "  try${try}: menu captured key=$($p.key) itemPos=$itemPos" -ForegroundColor Green; break }
            }
        }
        if (-not $menuKey) { Write-Host "  try${try}: no menu popup (found $($pops.Count) popups)" -ForegroundColor DarkGray }
    }
    $w.Dispose()
}
if (-not $menuKey) {
    Write-Host "  menu not captured; using DIRECT popup/0 (confirmed open by abort) path [7]" -ForegroundColor Yellow
    $menuKey = "popup/0"; $itemPos = 7
    # need a fresh epoch
    Start-Sleep -Milliseconds 200
    $w = New-WS; Open-UI $w; $s = Snap $w; if ($s.snap) { $usedEpoch = $s.snap.sepoch }; $w.Dispose()
}

Write-Host "`n### menu_click path=[$itemPos] on $menuKey ###" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $menuKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $usedEpoch + '}'
Write-Host "  SEND: $msg"
$w = New-WS; Open-UI $w; $s3 = Snap $w; if ($s3.snap) { $usedEpoch = $s3.snap.sepoch }
$msg = '{"t":"act","key":"' + $menuKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $usedEpoch + '}'
Send-WS $w $msg
$d3 = Drain $w 4
Write-Host "  after menu_click: ok=$($d3.ok)" -ForegroundColor $(if($d3.ok){"Green"}else{"Yellow"})
foreach ($m in $d3.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "    act_result ok=$($p.ok)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
$w.Dispose()

Write-Host "`n### find msgbox + Co ###" -ForegroundColor Magenta
$coKey = $null; $msgSnap = $null
for ($try = 1; $try -le 8 -and -not $coKey; $try++) {
    Start-Sleep -Milliseconds 350
    $w = New-WS; Open-UI $w
    $s = Snap $w
    if ($s.snap) {
        $msgSnap = $s.snap
        $mbx = foreach ($n in $s.snap.b.children) { if ($n.popup -eq $true -and $n.kind -eq "msgbox") { $n } }
        if ($mbx) {
            foreach ($ch in $mbx.children) { if ($ch.kind -eq "button" -and $ch.id -eq 6) { $coKey = $ch.key } }
            if (-not $coKey) { foreach ($ch in $mbx.children) { if ($ch.kind -eq "button") { $coKey = $ch.key; break } } }
            Write-Host "  try${try}: msgbox coKey=$coKey" -ForegroundColor Green
        } else { Write-Host "  try${try}: no msgbox yet" -ForegroundColor DarkGray }
    }
    $w.Dispose()
}
if (-not $coKey) { Write-Host "FAIL: no confirm msgbox" -ForegroundColor Red; exit 1 }

Write-Host "`n### toggle Co ($coKey) ###" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $coKey + '","op":"toggle","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
Write-Host "  SEND: $msg"
$w = New-WS; Open-UI $w; $s5 = Snap $w; if ($s5.snap) { $msgSnap = $s5.snap }
$msg = '{"t":"act","key":"' + $coKey + '","op":"toggle","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
Send-WS $w $msg
Start-Sleep -Milliseconds 800
$d5 = Drain $w 4
Write-Host "  after toggle: ok=$($d5.ok)" -ForegroundColor $(if($d5.ok){"Green"}else{"Yellow"})
foreach ($m in $d5.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "act_result") { Write-Host "    act_result ok=$($p.ok)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) } }
$w.Dispose()
Write-Host "  sent toggle Co" -ForegroundColor Green

Write-Host "`n### VERIFY local (wait 20s) ###" -ForegroundColor Magenta
Start-Sleep -Seconds 20
$db = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\client_database.json" -Raw | ConvertFrom-Json
$clientId = ($db.clients | Where-Object { [int]$_.idx -eq $TARGET }).client
Write-Host "  target client: $clientId" -ForegroundColor Cyan
$left = @(Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match "$clientId" })
if ($left.Count) { $left | ForEach-Object { Write-Host "  STILL RUNNING PID=$($_.Id) $($_.MainWindowTitle)" -ForegroundColor Red } } else { Write-Host "  $clientId process GONE" -ForegroundColor Green }
Write-Host "  total qnyh: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Gray