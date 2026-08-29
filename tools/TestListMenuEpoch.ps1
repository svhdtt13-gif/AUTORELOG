#TestListMenuEpoch.ps1 - Try list_menu with correct epoch and proper format
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()

function Send-($m) { 
    Write-Host ">> $m" -ForegroundColor DarkGray
    $b = [System.Text.Encoding]::UTF8.GetBytes($m)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait()
}

function RecvAll($secs) {
    $all = @()
    $buf = New-Object byte[] 1048576
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) { $all += $p }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    return $all
}

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
$msgs = RecvAll 1
Send- '{"t":"launch","product_id":73}'
$msgs2 = RecvAll 3

# Find sepoch from any message that has it
$sepoch = 0
foreach ($m in ($msgs + $msgs2)) {
    if ($m.sepoch) { $sepoch = $m.sepoch }
    if ($m.t -eq "snapshot" -and $m.sepoch) { $sepoch = $m.sepoch }
}
Write-Host "sepoch=$sepoch" -ForegroundColor Cyan

# Try list_menu with correct epoch
$actId = "act_$(Get-Random)"
$epoch = $sepoch

Write-Host "`n=== list_menu r=5 epoch=$epoch ===" -ForegroundColor Yellow
$actMsg = @{ t = "act"; key = "root/1000#0"; op = "list_menu"; r = 5; id = $actId; epoch = $epoch } | ConvertTo-Json -Compress
Send- $actMsg

$msgs3 = RecvAll 5
foreach ($m in $msgs3) {
    if ($m.t -eq "act_result") {
        Write-Host "ACT_RESULT: ok=$($m.ok) reason=$($m.reason) id=$($m.id)" -ForegroundColor $(if ($m.ok) { "Green" } else { "Red" })
    }
    elseif ($m.t -eq "snapshot") {
        Write-Host "snapshot gen=$($m.gen) sepoch=$($m.sepoch)" -ForegroundColor Green
        # Check for popup/menu
        $found = $false
        function Find-Popup($node) {
            if ($node.popup -eq $true -or $node.kind -eq "menu" -or $node.kind -eq "msgbox") {
                Write-Host "  POPUP! kind=$($node.kind) id=$($node.id) vis=$($node.vis) key=$($node.key)" -ForegroundColor Red
                if ($node.items) {
                    foreach ($item in $node.items) {
                        $txt = if ($item.text) { $item.text } elseif ($item.t) { $item.t } else { "?" }
                        Write-Host "    item: '$txt' id=$($item.id) dis=$($item.dis)" -ForegroundColor Red
                    }
                }
                if ($node.children) {
                    foreach ($c in $node.children) {
                        $txt = if ($c.text) { $c.text } else { "" }
                        Write-Host "    child: $($c.kind) '$txt' id=$($c.id)" -ForegroundColor Red
                    }
                }
                $script:found = $true
            }
            if ($node.children) { foreach ($c in $node.children) { Find-Popup $c } }
        }
        Find-Popup $m.b
        if (-not $found) { Write-Host "  No popup found in snapshot" -ForegroundColor Gray }
        $m | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_listmenu.json" -Encoding UTF8
    }
    else { Write-Host "<< $($m.t)" -ForegroundColor DarkGray }
}

Write-Host "`nState: $($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
