#CloseEmulator.ps1 - FULL CLOSE an emulator client via remote (proven mechanism)
# Usage: powershell -File CloseEmulator.ps1 -Row <idx> [-NoConfirm]
param(
    [Parameter(Mandatory=$true)][int]$Row,
    [switch]$NoConfirm
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
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
function Get-Snapshot($ws, [int]$secs) {
    foreach ($raw in (Drain $ws $secs)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
    return $null
}
function Connect-and-Snap { $w = New-WS; Open-UI $w; $s = Get-Snapshot $w 6; return @{ ws = $w; snap = $s } }
function Scan-Popup($node) {
    $r = $null
    if ($node.popup -eq $true -and $node.kind -eq "menu") { $r = $node }
    if (-not $r -and $node.children) { foreach ($c in $node.children) { $r = Scan-Popup $c; if ($r) { break } } }
    return $r
}

Write-Host ("[CloseEmulator] Closing row {0} ..." -f $Row) -ForegroundColor Cyan
if ($NoConfirm) { Write-Host "  [warn] NoConfirm switch ignored - confirmation dialog is automated anyway" -ForegroundColor DarkGray }

# 1. open row menu
$c1 = Connect-and-Snap
if (-not $c1.snap) { throw "no snapshot on step1" }
Send-WS $c1.ws ('{"t":"act","k":"root/1000#0","op":"list_menu","r":' + $Row + '}')
Start-Sleep -Milliseconds 300
$c1.ws.Dispose()

# 2. find popup + item cmd=32773 (Tat gia lap)
$popupKey = $null; $itemPos = $null; $snapTmp = $null
for ($try = 1; $try -le 6 -and -not $popupKey; $try++) {
    Start-Sleep -Milliseconds 400
    $c = Connect-and-Snap
    if ($c.snap) {
        $snapTmp = $c.snap
        $pc = Scan-Popup $c.snap.b
        if ($pc) { $popupKey = $pc.key; $it2 = $pc.items | Where-Object { $_.cmd -eq 32773 }; if ($it2) { $itemPos = $it2.pos } }
    }
    $c.ws.Dispose()
}
if (-not $popupKey) { throw "popup not found" }
Write-Host "  popup=$popupKey itemPos=$itemPos" -ForegroundColor Gray

# 3. menu_click path=[itemPos] -> triggers confirm msgbox
$id = Make-Id
$msg = '{"t":"act","key":"' + $popupKey + '","op":"menu_click","path":[' + $itemPos + '],"id":"' + $id + '","epoch":' + $snapTmp.sepoch + '}'
$c3 = Connect-and-Snap
if ($c3.snap) { Send-WS $c3.ws $msg; Start-Sleep -Milliseconds 600 }
$c3.ws.Dispose()
Write-Host "  sent menu_click -> msgbox expect" -ForegroundColor Gray

# 4. find msgbox C0 button key (popup/.../6#0)
$coKey = $null; $msgSnap = $null
for ($try = 1; $try -le 6 -and -not $coKey; $try++) {
    Start-Sleep -Milliseconds 400
    $c = Connect-and-Snap
    if ($c.snap) {
        $msgSnap = $c.snap
        foreach ($n in $c.snap.b.children) {
            if ($n.popup -eq $true -and $n.kind -eq "msgbox") {
                if ($n.children) { foreach ($ch in $n.children) { if ($ch.kind -eq "button" -and $ch.id -eq 6) { $coKey = $ch.key } } }
                if (-not $coKey) { foreach ($ch in $n.children) { if ($ch.kind -eq "button") { $coKey = $ch.key; break } } }
            }
        }
    }
    $c.ws.Dispose()
}
if (-not $coKey) { throw "confirm button not found" }
Write-Host "  coKey=$coKey" -ForegroundColor Gray

# 5. toggle the Co button (op=toggle is the ONLY working op)
$id = Make-Id
$msg = '{"t":"act","key":"' + $coKey + '","op":"toggle","id":"' + $id + '","epoch":' + $msgSnap.sepoch + '}'
$c5 = Connect-and-Snap
if ($c5.snap) { Send-WS $c5.ws $msg; Start-Sleep -Milliseconds 800 }
$c5.ws.Dispose()
Write-Host "  sent toggle Co -> emulator should close" -ForegroundColor Gray

# 6. verify remote state
Start-Sleep -Seconds 10
$c6 = Connect-and-Snap
$result = @{ row = $Row; closed = $false; totalRunning = -1 }
if ($c6.snap) {
    Send-WS $c6.ws '{"t":"scr_list"}'
    for ($n = 0; $n -lt 3 -and $c6.ws.State -eq "Open"; $n++) {
        foreach ($raw in (Drain $c6.ws 6)) {
            if ($c6.ws.State -ne "Open") { break }
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "scr_list_res") {
                $i = $p.instances | Where-Object { $_.idx -eq $Row }
                $run = @($p.instances | Where-Object { $_.state -eq 'running' })
                $result.totalRunning = $run.Count
                if ($i -and $i.state -ne 'running') { $result.closed = $true }
            }
        }
    }
}
$c6.ws.Dispose()
Write-Host ("[CloseEmulator] row {0}: closed={1} running={2}/27" -f $Row, $result.closed, $result.totalRunning) -ForegroundColor $(if($result.closed){"Green"}else{"Red"})
$result | ConvertTo-Json