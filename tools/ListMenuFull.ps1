#ListMenuFull.ps1 - list_menu r=9 with FULL key + id + epoch (learned format)
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
function Dump($p) {
    if ($p.t -eq "snapshot") {
        Write-Host "  SNAPSHOT gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor DarkGray
        # find menu/popup/dialog anywhere & print rows
        foreach ($n in $p.b.children) {
            if ($n.key -match 'popup|menu|dialog') { Write-Host "    child key=$($n.key) kind=$($n.kind) text='$(($n.text -replace '[^\x20-\x7E]','.'))'" -ForegroundColor Green }
        }
    }
    elseif ($p.t -eq "delta") { Write-Host "  delta" -ForegroundColor DarkGray }
    elseif ($p.t -eq "act_result") { Write-Host "  act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
}

# Variant A: full key + id + epoch (like row_toggle)
foreach ($variant in @("A","B")) {
    Write-Host "`n===== VARIANT $variant =====" -ForegroundColor Magenta
    $ws = New-WS; Open-UI $ws
    $epoch = 0
    foreach ($raw in (Drain $ws 5)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { $epoch = $p.sepoch } }
    $id = Make-Id
    $msg = ""
    if ($variant -eq "A") { $msg = '{"t":"act","key":"root/1000#0","op":"list_menu","r":9,"id":"' + $id + '","epoch":' + $epoch + '}' }
    else { $msg = '{"t":"act","key":"root/1000#0","op":"list_menu","r":9}' }
    Write-Host "  SEND: $msg" -ForegroundColor Yellow
    Send-WS $ws $msg
    for ($n = 0; $n -lt 3; $n++) {
        foreach ($raw in (Drain $ws 2)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; Dump $p }
        if ($ws.State -ne "Open") { break }
        Start-Sleep -Milliseconds 300
    }
    Write-Host "  state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
    $ws.Dispose()
    Start-Sleep -Milliseconds 600
}