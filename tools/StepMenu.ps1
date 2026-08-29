#StepMenu.ps1 - reopen row9, query scr_list, capture r=-1 popup items (no click)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 1048576

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
function Show-Inst($p) {
    if ($p.t -eq "scr_list_res" -and $p.instances) {
        Write-Host "  scr_list_res: instances=$($p.instances.Count)" -ForegroundColor Cyan
        foreach ($inst in $p.instances | Where-Object { $_.idx -in @(0,9) }) {
            Write-Host "    idx $($inst.idx) id=$($inst.id) state=$($inst.state) cap=$($inst.cap)" -ForegroundColor $(if($inst.state -eq 'running'){"Green"}else{"Gray"})
        }
    }
}
function Show-Rows($snap) {
    foreach ($n in $snap.b.children) {
        if ($n.key -eq "root/1000#0") {
            foreach ($row in $n.rows | Where-Object { $_.r -in @(0,9) }) { Write-Host "  row $($row.r) chk=$($row.checked)" -ForegroundColor $(if($row.checked -eq 1){"Green"}else{"Red"}) }
        }
    }
}
function Show-All($raws, [string]$tag) {
    foreach ($raw in $raws) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { Write-Host "  [$tag] snapshot gen=$($p.gen) sepoch=$($p.sepoch)"; Show-Rows $p }
        elseif ($p.t -eq "scr_list_res") { Write-Host "  [$tag]"; Show-Inst $p }
        elseif ($p.t -eq "act_result") { Write-Host "  [$tag] act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
        elseif ($p.t -eq "delta") { Write-Host "  [$tag] delta" -ForegroundColor DarkGray }
    }
}

Write-Host "`n### STEP 0: query scr_list + recheck rows ###" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
Show-All (Drain $ws 4) "connect"
Write-Host "sending scr_list..." -ForegroundColor Yellow
Send-WS $ws '{"t":"scr_list"}'
Show-All (Drain $ws 3) "scr_list"
$epoch = 0
foreach ($raw in (@() + (Drain $ws 2))) { $q = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($q.t -eq "snapshot") { $epoch = $q.sepoch } }
Write-Host "epoch=$epoch" -ForegroundColor DarkGray

Write-Host "`n### STEP 1: reopen row 9 (was left off) ###" -ForegroundColor Magenta
if ($epoch -eq 0) { foreach ($raw in (Drain $ws 6)) { $q = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($q.t -eq "snapshot") { $epoch = $q.sepoch } } }
$id = Make-Id
$msg = '{"t":"act","key":"root/1000#0","op":"row_toggle","r":9,"id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "SEND: $msg"
Send-WS $ws $msg
Show-All (Drain $ws 5) "reopen"
Write-Host "state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
$ws.Dispose()
Start-Sleep -Seconds 4

Write-Host "`n### STEP 2: reopen check + then list_menu r=-1 (capture only, no click) ###" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
$epoch = 0; $snap2 = $null
foreach ($raw in (Drain $ws 5)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Show-Rows $p }
    elseif ($p.t -eq "scr_list_res") { Show-Inst $p }
}
if (-not $epoch) { $epoch = 37 }
Write-Host "epoch=$epoch sending list_menu r=-1..." -ForegroundColor Yellow
Send-WS $ws '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}'
foreach ($raw in (Drain $ws 5)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") {
        foreach ($n in $p.b.children) {
            $txt = ($n.text -replace '[^\x20-\x7E]','.')
            if ($n.key -match 'popup' -or $n.kind -match 'menu') {
                Write-Host "  POPUP key=$($n.key) kind=$($n.kind) text='$txt'" -ForegroundColor Green
                if ($n.children) { foreach ($c in $n.children) { Write-Host "     item key=$($c.key) kind=$($c.kind) text='$(($c.text -replace '[^\x20-\x7E]','.'))' en=$($c.en)" -ForegroundColor Yellow } }
            }
        }
    }
    elseif ($p.t -eq "delta") { Write-Host "  delta" -ForegroundColor DarkGray }
}
Write-Host "state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
$ws.Dispose()