#DumpTreeAfterMenu.ps1 - list_menu r=9 then reconnect, dump FULL tree, find popup/"tắt giả lập"
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

for ($attempt = 1; $attempt -le 3; $attempt++) {
    Write-Host "`n=== ATTEMPT $attempt : list_menu r=9 then fast dump ===" -ForegroundColor Magenta
    $ws = New-WS; Open-UI $ws
    foreach ($raw in (Drain $ws 4)) { $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue }
    Send-WS $ws '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
    Start-Sleep -Milliseconds 200
    $ws.Dispose()

    Start-Sleep -Milliseconds 250
    $ws = New-WS; Open-UI $ws
    $snap = $null
    foreach ($raw in (Drain $ws 5)) {
        $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($p.t -eq "snapshot") { $snap = $p }
    }
    if ($snap) {
        $outFile = "C:\Users\ADMIN\Documents\ai tool\tools\after_menu_attempt$attempt.json"
        $snap | ConvertTo-Json -Depth 15 | Out-File $outFile -Encoding UTF8
        Write-Host "  Saved $outFile ($((Get-Item $outFile).Length) bytes)" -ForegroundColor Green
        # Find any node with popup key or text containing tắt/giả lập
        $found = @()
        function Walk($node, $d) {
            $txt = $node.text
            if ($node.key -match 'popup|menu' -or ($txt -and ($txt -match 'tắt|giả lập|Tắt giả lập'))) {
                $script:mh += $node
            }
            if ($node.children) { foreach ($c in $node.children) { Walk $c ($d+1) } }
        }
        $script:mh = @()
        Walk $snap.b 0
        if ($script:mh) {
            Write-Host "  FOUND:" -ForegroundColor Green
            $i = 1
            foreach ($md in $script:mh) {
                Write-Host "    [$i] key=$($md.key) kind=$($md.kind) text='$($md.text)' en=$($md.en)" -ForegroundColor Yellow
                if ($md.children) { foreach ($mc in $md.children) { Write-Host "          item key=$($mc.key) kind=$($mc.kind) text='$($mc.text)' en=$($mc.en)" -ForegroundColor Cyan } }
                $i++
            }
            break
        } else {
            Write-Host "  no popup found (tree dumped)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  no snapshot on reconnect" -ForegroundColor Red
    }
    $ws.Dispose()
    Start-Sleep -Milliseconds 400
}
Write-Host "`nDone"