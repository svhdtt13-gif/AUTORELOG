#CheckPopup.ps1 - Check if list_menu created a popup in snapshot
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

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 500
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500

# Drain initial messages
$buf = New-Object byte[] 1048576
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try { $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } }; if ($ms.Length -gt 0) { $ms.Dispose() } else { $ms.Dispose(); break } } catch { break }
}

Write-Host "Drained initial messages" -ForegroundColor Green

# Now send list_menu
Write-Host "`nSending list_menu r=-1..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}'
Start-Sleep -Seconds 2

# Collect all messages and check for snapshot with popup
$foundPopup = $false
$timeout2 = [DateTime]::UtcNow.AddSeconds(5)
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "snapshot") {
                    Write-Host "snapshot gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor Green
                    $raw | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_listmenu.json" -Encoding UTF8
                    
                    # Check for popup nodes
                    function Find-Popup($node, $depth) {
                        if ($node.popup -eq $true) {
                            $txt = if ($node.title) { $node.title } elseif ($node.text) { $node.text } else { "" }
                            Write-Host "  POPUP at depth $depth! kind=$($node.kind) id=$($node.id) key=$($node.key) title='$txt' vis=$($node.vis)" -ForegroundColor Red
                            $script:foundPopup = $true
                            
                            if ($node.items) {
                                Write-Host "  ITEMS:" -ForegroundColor Red
                                foreach ($item in $node.items) {
                                    $itemText = if ($item.text) { $item.text } elseif ($item.t) { $item.t } else { "?" }
                                    Write-Host "    '$itemText' id=$($item.id) dis=$($item.dis) key=$($item.key)" -ForegroundColor Red
                                }
                            }
                            if ($node.children) {
                                Write-Host "  CHILDREN:" -ForegroundColor Red
                                foreach ($c in $node.children) {
                                    $cText = if ($c.text) { $c.text } elseif ($c.title) { $c.title } else { "" }
                                    Write-Host "    $($c.kind) '$cText' id=$($c.id) key=$($c.key)" -ForegroundColor Red
                                    if ($c.children) {
                                        foreach ($cc in $c.children) {
                                            $ccText = if ($cc.text) { $cc.text } else { "" }
                                            Write-Host "      $($cc.kind) '$ccText' id=$($cc.id) key=$($cc.key)" -ForegroundColor Red
                                        }
                                    }
                                }
                            }
                        }
                        if ($node.children) { foreach ($c in $node.children) { Find-Popup $c ($depth + 1) } }
                    }
                    Find-Popup $p.b 0
                }
                elseif ($p.t -eq "act_result") { Write-Host "act_result: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Cyan }
                elseif ($p.t -eq "delta") { Write-Host "delta" -ForegroundColor DarkGray }
                else { Write-Host "$($p.t)" -ForegroundColor Gray }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if (-not $foundPopup) { Write-Host "`nNO POPUP FOUND in snapshot" -ForegroundColor Red }
$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
