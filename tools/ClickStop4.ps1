#ClickStop4.ps1 - list_menu r=5 for client-specific menu
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

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# list_menu r=5 (specific row)
Write-Host "list_menu r=5..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}'

$buf = New-Object byte[] 1048576
$popupKey = $null
$sepoch = 0
$timeout = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                $sepoch = $p.sepoch
                Write-Host "snapshot gen=$($p.gen) sepoch=$sepoch" -ForegroundColor Green
                
                # Find popup and list items
                function Scan-All($node, $path) {
                    if ($node.popup -eq $true) {
                        $txt = if ($node.title) { $node.title } else { $node.kind }
                        Write-Host "  POPUP: kind=$($node.kind) key=$($node.key) title='$txt'" -ForegroundColor Red
                        if ($node.items) {
                            $i = 0
                            foreach ($item in $node.items) {
                                $t = if ($item.t) { $item.t } else { "?" }
                                $dis = if ($item.dis) { " [DIS]" } else { "" }
                                Write-Host "    [$i] '$t'$dis" -ForegroundColor Red
                                $i++
                            }
                        }
                        if ($node.children) {
                            foreach ($c in $node.children) {
                                $ct2 = if ($c.text) { $c.text } else { "" }
                                Write-Host "    child: $($c.kind) '$ct2' key=$($c.key)" -ForegroundColor Red
                            }
                        }
                        $script:popupKey = $node.key
                    }
                    if ($node.children) { foreach ($c in $node.children) { Scan-All $c "$path/$($c.id)" } }
                }
                Scan-All $p.b "root"
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_rowmenu.json" -Encoding UTF8
            }
            elseif ($p.t -eq "act_result") { Write-Host "act_result: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Cyan }
            else { Write-Host "$($p.t)" -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if ($popupKey) {
    Write-Host "`nClicking stop item..." -ForegroundColor Yellow
    $actId = "mc_$(Get-Random)"
    $msg = @{ t = "act"; k = $popupKey; op = "menu_click"; path = @(7); id = $actId; epoch = $sepoch } | ConvertTo-Json -Compress
    Write-Host "Send: $msg" -ForegroundColor DarkGray
    Send- $msg
    
    $timeout2 = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") { Write-Host "RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
                elseif ($p.t -eq "scr_list_res") { Write-Host "scr_list_res" -ForegroundColor Cyan }
                elseif ($p.t -eq "snapshot") { Write-Host "snapshot" -ForegroundColor Green }
                else { Write-Host "$($p.t)" -ForegroundColor Gray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
}

Write-Host "state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
