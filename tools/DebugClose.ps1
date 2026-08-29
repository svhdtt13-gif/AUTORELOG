#DebugClose.ps1 - step by step close on row 9 with full logging to find the failure point
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 2097152
$TARGET = 9

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
    return @{ ok = ($ws.State -eq "Open"); msgs = $out }
}
function Open-UI($ws) { Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300; Send-WS $ws '{"t":"launch","product_id":73}' }
function Make-Id { $c = "abcdefghijklmnopqrstuvwxyz0123456789"; $a = ""; for ($i=0;$i -lt 5;$i++){ $a += $c[(Get-Random -Maximum $c.Length)] }; "$a`:1" }
function Snap($ws) { $r = Drain $ws 6; foreach ($m in $r.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return @{ snap = $p; ok = $r.ok } } }; return @{ snap = $null; ok = $r.ok } }
function Scan-Popup($node) { if ($node.popup -eq $true -and $node.kind -eq "menu") { return $node }; if ($node.children) { foreach ($c in $node.children) { $r = Scan-Popup $c; if ($r) { return $r } } }; return $null }

Write-Host "### STEP 1: list_menu r=$TARGET" -ForegroundColor Magenta
$w = New-WS; Open-UI $w
$s1 = Snap $w
Write-Host "  epoch=$($s1.snap.sepoch) ok=$($s1.ok)" -ForegroundColor Cyan
Send-WS $w ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $TARGET + '}')
$d1 = Drain $w 3
Write-Host "  after list_menu: ok=$($d1.ok) msgs=$($d1.msgs.Count)" -ForegroundColor $(if($d1.ok){"Green"}else{"Red"})
foreach ($m in $d1.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "    [$($p.t)] epoch=$($p.sepoch)" -ForegroundColor DarkGray }
$w.Dispose()

Write-Host "`n### STEP 2: reconnect, find popup" -ForegroundColor Magenta
$popupKey=$null; $itemPos=$null; $snapTmp=$null
for ($try=1; $try -le 6 -and -not $popupKey; $try++) {
    Start-Sleep -Milliseconds 400
    $w = New-WS; Open-UI $w
    $s = Snap $w
    if ($s.snap) {
        $snapTmp = $s.snap
        $pc = Scan-Popup $s.snap.b
        if ($pc) { $popupKey = $pc.key; $it = $pc.items | Where-Object { $_.cmd -eq 32773 }; if ($it) { $itemPos = $it.pos }; Write-Host "  try${try}: popup=$($pc.key) items=$($pc.items.Count) itemPos=$itemPos" -ForegroundColor Green }
        else { Write-Host "  try${try}: snapshot but no menu popup" -ForegroundColor DarkGray }
    } else { Write-Host "  try${try}: no snapshot" -ForegroundColor DarkGray }
    $w.Dispose()
}
if (-not $popupKey) { Write-Host "FAIL: no popup" -ForegroundColor Red; exit }

Write-Host "`n### STEP 3: menu_click path=[$itemPos]" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $popupKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $snapTmp.sepoch + '}'
Write-Host "  SEND: $msg" -ForegroundColor Yellow
$w = New-WS; Open-UI $w
$s3 = Snap $w
Write-Host "  pre-epoch=$($s3.snap.sepoch)"
Send-WS $w $msg
$d3 = Drain $w 4
Write-Host "  after menu_click: ok=$($d3.ok) msgs=$($d3.msgs.Count)" -ForegroundColor $(if($d3.ok){"Green"}else{"Red"})
foreach ($m in $d3.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "    [$($p.t)] okmsg=$(if($p.t -eq 'act_result'){"ok=$($p.ok) reason=$($p.reason)"}else{''})" -ForegroundColor DarkGray }
$w.Dispose()

Write-Host "`n### STEP 4: find msgbox + Co" -ForegroundColor Magenta
$coKey=$null; $msgSnap=$null
for ($try=1; $try -le 6 -and -not $coKey; $try++) {
    Start-Sleep -Milliseconds 400
    $w = New-WS; Open-UI $w
    $s = Snap $w
    if ($s.snap) {
        $msgSnap = $s.snap
        $mbx = $null
        foreach ($n in $s.snap.b.children) { if ($n.popup -eq $true -and $n.kind -eq "msgbox") { $mbx = $n } }
        if ($mbx) {
            foreach ($ch in $mbx.children) { if ($ch.kind -eq "button" -and $ch.id -eq 6) { $coKey = $ch.key } }
            if (-not $coKey) { foreach ($ch in $mbx.children) { if ($ch.kind -eq "button") { $coKey = $ch.key; break } } }
            Write-Host "  try${try}: msgbox found, coKey=$coKey" -ForegroundColor Green
        } else { Write-Host "  try${try}: no msgbox" -ForegroundColor DarkGray }
    } else { Write-Host "  try${try}: no snapshot" -ForegroundColor DarkGray }
    $w.Dispose()
}
if (-not $coKey) { Write-Host "FAIL: no msgbox" -ForegroundColor Red; exit }

Write-Host "`n### STEP 5: toggle Co" -ForegroundColor Magenta
$id = Make-Id
$msg = '{"t":"act","key":"' + $coKey + '","op":"toggle","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
Write-Host "  SEND: $msg" -ForegroundColor Yellow
$w = New-WS; Open-UI $w
$s5 = Snap $w
Write-Host "  pre-epoch=$($s5.snap.sepoch)"
Send-WS $w $msg
$d5 = Drain $w 4
Write-Host "  after toggle: ok=$($d5.ok) msgs=$($d5.msgs.Count)" -ForegroundColor $(if($d5.ok){"Green"}else{"Red"})
foreach ($m in $d5.msgs) { $p = $m | ConvertFrom-Json -ErrorAction SilentlyContinue; Write-Host "    [$($p.t)]" -ForegroundColor DarkGray }
$w.Dispose()

Write-Host "`n### VERIFY local (wait 15s)" -ForegroundColor Magenta
Start-Sleep -Seconds 15
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'khoqua09|client_7' } | ForEach-Object { Write-Host "  STILL RUNNING PID=$($_.Id)" -ForegroundColor Red }
Write-Host "  total qnyh: $(@(Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor Gray