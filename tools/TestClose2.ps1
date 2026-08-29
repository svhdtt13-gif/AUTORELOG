#TestClose2.ps1 - Clean close test on row 9
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$script:token = $data.session
$script:appRoom = "e1c51deba15917ba"
$script:ct = [System.Threading.CancellationToken]::None
$script:buf = New-Object byte[] 1048576

$script:sess = $null
function New-WS {
    $sess = New-Object System.Net.WebSockets.ClientWebSocket
    $sess.Options.SetRequestHeader("Authorization", "Bearer $script:token")
    $sess.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$($script:appRoom)&session=$($script:token)")
    $sess.ConnectAsync($uri, $script:ct).Wait()
    $script:sess = $sess
    return $sess
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $script:ct).Wait() }
# Receive messages until we find one with t == $wantType (or timeout). Returns the parsed object (or null).
function Get-Msg($ws, [string]$wantType, [int]$secs = 6) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$script:buf)), $script:ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($script:buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $json = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                $p = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p -and $p.t -eq $wantType) { $ms.Dispose(); return $p }
                if ($p -and $p.t -in @('act_result','delta')) { $ms.Dispose(); if ($p.t -eq 'act_result') { Write-Host "    [act_result ok=$($p.ok) reason=$($p.reason)]" -ForegroundColor $(if ($p.ok){"Green"}else{"Red"}) } }
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $null
}
function Open-UI($ws) {
    Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
    Send-WS $ws '{"t":"launch","product_id":73}'
    Get-Msg $ws "snapshot" 8
}
function Show-Rows($snap, [string]$label) {
    Write-Host "  [$label] epoch=$($snap.sepoch)" -ForegroundColor DarkGray
    foreach ($n in $snap.b.children) {
        if ($n.key -eq "root/1000#0") {
            foreach ($row in $n.rows) { Write-Host "    row $($row.r) checked=$($row.checked)  $(if($row.checked -eq 1){'[RUN]'}else{'[off]'})" -ForegroundColor $(if($row.checked -eq 1){"Green"}else{"Gray"}) }
        }
    }
}
function Make-Id {
    $chars = "abcdefghijklmnopqrstuvwxyz0123456789"; $Ah = ""
    for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
    return "$Ah`:1"
}

Write-Host "`n### STEP 0: Current state ###" -ForegroundColor Magenta
$ws = New-WS; Write-Host "Connected: $($ws.State)"
$snap = Open-UI $ws
if (-not $snap) { Write-Host "No snapshot - aborting" -ForegroundColor Red; exit 1 }
Show-Rows $snap "before"

Write-Host "`n### STEP 1: list_menu r=9 ###" -ForegroundColor Magenta
Send-WS $ws '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
$popup = Get-Msg $ws "snapshot" 8
if ($popup) {
    $butYes = $null
    Write-Host "Dialog nodes:" -ForegroundColor Yellow
    foreach ($n in $popup.b.children) {
        $txt = ($n.text -replace '[^\x20-\x7E]','')
        if ($n.key -match 'popup') {
            Write-Host "  key=$($n.key) kind=$($n.kind) title='$txt'" -ForegroundColor Cyan
            if ($n.children) { foreach ($c in $n.children) { $ctxt = ($c.text -replace '[^\x20-\x7E]',''); Write-Host "    child key=$($c.key) kind=$($c.kind) text='$ctxt'" -ForegroundColor DarkGray; if ($ctxt -match 'Có|Co') { $butYes = $c.key } } }
        }
    }
    if (-not $butYes) { $butYes = "popup/0/6#0"; Write-Host "  (no Co found, default popup/0/6#0)" -ForegroundColor Yellow }
    Write-Host "`n### STEP 2: click '$butYes' ###" -ForegroundColor Magenta
    $id = Make-Id
    $msg = '{"t":"act","key":"' + $butYes + '","op":"click","id":"' + $id + '","epoch":' + $snap.sepoch + '}'
    Write-Host "  SEND: $msg"
    Send-WS $ws $msg
} else {
    Write-Host "No popup snapshot after list_menu (state=$($ws.State))" -ForegroundColor Red
}
Get-Msg $ws "snapshot" 4 | Out-Null
Write-Host "Final conn state: $($ws.State)" -ForegroundColor Cyan
$ws.Dispose()

Write-Host "`n### STEP 3: verify row 9 ###" -ForegroundColor Magenta
Start-Sleep -Seconds 5
$ws = New-WS; Write-Host "Connected: $($ws.State)"
$snap2 = Open-UI $ws
if ($snap2) { Show-Rows $snap2 "after" } else { Write-Host "No snapshot" -ForegroundColor Red }
$ws.Dispose()