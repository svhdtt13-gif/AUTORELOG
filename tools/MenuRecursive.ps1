#MenuRecursive.ps1 - list_menu r=9, recursive scan for popup/menu/dialog nodes
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

# Recursively collect all nodes; report popup/menu/dialog + any with text
function Traverse($node, $depth) {
    $txt = ($node.text -replace '[^\x20-\x7E]','.')
    $flag = ($node.key -match 'popup|menu|dialog|msgbox|btn|button') -or ($node.kind -match 'menu|dialog') -or ($txt -match '[\p{L}]*[a-zéèảãáà]' -and $txt.Trim().Length -gt 0)
    if ($flag) {
        Write-Host ("  {0}key={1} kind={2} en={3} text='{4}'" -f (' ' * $depth), $node.key, $node.kind, $node.en, $txt) -ForegroundColor Yellow
    }
    if ($node.children) { foreach ($c in $node.children) { Traverse $c ($depth + 1) } }
}
function Scan($raw, [string]$tag) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { Write-Host "`n--- [$tag] SNAPSHOT ---" -ForegroundColor Magenta; Traverse $p.b 1 }
    elseif ($p.t -eq "delta") { Write-Host "`n--- [$tag] DELTA ---" -ForegroundColor Magenta; if ($p.b) { Traverse $p.b 1 } }
    elseif ($p.t -eq "act_result") { Write-Host "  [$tag] act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if($p.ok){"Green"}else{"Red"}) }
}

Write-Host "### connect + snapshot ###" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
$epoch = 0
foreach ($raw in (Drain $ws 5)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Scan $raw "init" }
    elseif ($p.t -eq "scr_list_res") {
        Write-Host "  scr_list_res idx9: $(($p.instances | Where-Object {$_.idx -eq 9} | ConvertTo-Json -Compress))" -ForegroundColor DarkGray
    }
}
Write-Host "epoch=$epoch" -ForegroundColor Cyan

Write-Host "`n### SEND list_menu r=9 ###" -ForegroundColor Magenta
Send-WS $ws '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
foreach ($raw in (Drain $ws 4)) { Scan $raw "post-listmenu" }
Write-Host "state=$($ws.State)" -ForegroundColor $(if($ws.State -eq 'Open'){"Green"}else{"Red"})
$ws.Dispose()
Start-Sleep -Milliseconds 300

Write-Host "`n### reconnect + scan ###" -ForegroundColor Magenta
$ws = New-WS; Open-UI $ws
foreach ($raw in (Drain $ws 5)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { Scan $raw "reconnect" }; if ($p.t -eq "scr_list_res") { Write-Host "  scr_list_res idx9: $(($p.instances | Where-Object {$_.idx -eq 9} | ConvertTo-Json -Compress))" -ForegroundColor DarkGray } }
$ws.Dispose()