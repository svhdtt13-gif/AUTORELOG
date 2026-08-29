#TestCloseVerify.ps1 - Full close/reopen cycle on row 9 (client_7 khoqua09)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$script:token = $data.session
$script:appRoom = "e1c51deba15917ba"
$script:ct = [System.Threading.CancellationToken]::None
$script:buf = New-Object byte[] 1048576

function New-WS {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $script:token")
    $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$($script:appRoom)&session=$($script:token)")
    $ws.ConnectAsync($uri, $script:ct).Wait()
    return $ws
}
function Send-WS($ws, $m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $script:ct).Wait() }
function Receive-WS($ws, [int]$secs) {
    $buf = $script:buf; $timeout = [DateTime]::UtcNow.AddSeconds($secs); $msgs = @()
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $script:ct)
                if ($r.AsyncWaitHandle.WaitOne(800)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $msgs += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $msgs
}
function Get-Epoch($ws) {
    Send-WS $ws '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
    Send-WS $ws '{"t":"launch","product_id":73}'
    foreach ($raw in (Receive-WS $ws 6)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { return $p.sepoch }
    }
    return 0
}
function Get-RowState($ws, [int]$row) {
    foreach ($raw in (Receive-WS $ws 6)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") {
            foreach ($n in $p.b.children) { if ($n.key -eq "root/1000#0") { return ($n.rows | Where-Object { $_.r -eq $row }).checked } }
        }
    }
    return $null
}
function Make-Id {
    $chars = "abcdefghijklmnopqrstuvwxyz0123456789"; $Ah = ""
    for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
    return "$Ah`:1"
}

# ============ PHASE A: CLOSE row 9 ============
Write-Host "`n########## PHASE A: CLOSE row 9 (khoqua09) ##########" -ForegroundColor Magenta
$ws = New-WS
Write-Host "Connected: $($ws.State)"
$epoch = Get-Epoch $ws
Write-Host "epoch=$epoch, row9 before=$(Get-RowState $ws 9)" -ForegroundColor Cyan

Write-Host "`n[1] list_menu r=9..." -ForegroundColor Yellow
Send-WS $ws '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
$found = @()
foreach ($raw in (Receive-WS $ws 5)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") {
        foreach ($n in $p.b.children) {
            $txt = ($n.text -replace '[^\x20-\x7E]','')
            if ($n.kind -in @('dialog','contextmenu') -or $n.key -match 'popup') {
                Write-Host "  DIALOG key=$($n.key) kind=$($n.kind) title='$txt'" -ForegroundColor Green
                if ($n.children) {
                    foreach ($c in $n.children) { Write-Host "    child key=$($c.key) text='$(($c.text -replace '[^\x20-\x7E]',''))'" -ForegroundColor DarkGray; $found += $c.key }
                }
            }
        }
    }
}
Write-Host "State after list_menu: $($ws.State)" -ForegroundColor Cyan

$butYes = $null
foreach ($raw in (Receive-WS $ws 2)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") {
        foreach ($n in $p.b.children) {
            $txt = ($n.text -replace '[^\x20-\x7E]','')
            if ($n.key -match 'popup' -and $n.children) {
                foreach ($c in $n.children -join "`n" -split "`n") {}
                foreach ($c in $n.children) {
                    $ctxt = ($c.text -replace '[^\x20-\x7E]','')
                    Write-Host "    confirm child key=$($c.key) kind=$($c.kind) text='$ctxt'" -ForegroundColor DarkGray
                    if ($ctxt -match 'Có|Co|C\&ó|Yes') { $butYes = $c.key }
                }
            }
        }
    }
}

if (-not $butYes) {
    # Fallback: known key popup/0/6#0
    Write-Host "  No 'Co' button found by text, using popup/0/6#0" -ForegroundColor Yellow
    $butYes = "popup/0/6#0"
}
Write-Host "`n[2] Click button: $butYes" -ForegroundColor Yellow
$id = Make-Id
$msg = '{"t":"act","key":"' + $butYes + '","op":"click","id":"' + $id + '","epoch":' + $epoch + '}'
Write-Host "  SEND: $msg"
Send-WS $ws $msg
foreach ($raw in (Receive-WS $ws 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
    elseif ($p.t -eq "snapshot") { Write-Host "  snapshot gen=$($p.gen)" -ForegroundColor Gray }
    else { Write-Host "  $($p.t)" -ForegroundColor Gray }
}
Write-Host "State after click: $($ws.State)" -ForegroundColor Cyan; $ws.Dispose()

# ============ PHASE B: VERIFY close ============
Write-Host "`n########## PHASE B: VERIFY row 9 ##########" -ForegroundColor Magenta
Start-Sleep -Seconds 3
$ws = New-WS
Write-Host "Connected: $($ws.State)"
Get-Epoch $ws | Out-Null
$row9 = Get-RowState $ws 9
Write-Host "row9 after close attempt = $row9  $(if ($row9 -eq 0) { '[CLOSED OK]' } else { '[STILL RUNNING]' })" -ForegroundColor $(if ($row9 -eq 0) { "Green" } else { "Red" })