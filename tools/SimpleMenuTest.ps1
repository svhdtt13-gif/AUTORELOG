#SimpleMenuTest.ps1 - Just caps -> launch -> list_menu -> collect
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
Write-Host "Connected state=$($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

# Caps
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300

# Launch  
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# List menu immediately
Write-Host "Sending list_menu..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}'

# Collect ALL messages for 8 seconds
$buf = New-Object byte[] 1048576
$timeout = [DateTime]::UtcNow.AddSeconds(8)
$count = 0
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $count++
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p) {
                if ($p.t -eq "snapshot") {
                    Write-Host "[$count] SNAPSHOT gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor Green
                    
                    # Check ALL nodes
                    $foundPopup = $false
                    function Scan-Node($node, $path) {
                        if ($node.popup -eq $true -or $node.kind -eq "menu" -or $node.kind -eq "msgbox") {
                            Write-Host "  POPUP at $path! kind=$($node.kind) vis=$($node.vis) key=$($node.key)" -ForegroundColor Red
                            $script:foundPopup = $true
                            if ($node.items) {
                                foreach ($item in $node.items) {
                                    $t = if ($item.t) { $item.t } elseif ($item.text) { $item.text } else { "?" }
                                    Write-Host "    item: '$t'" -ForegroundColor Red
                                }
                            }
                        }
                        if ($node.children) { 
                            $idx = 0
                            foreach ($c in $node.children) { 
                                Scan-Node $c "$path/$idx"
                                $idx++
                            } 
                        }
                    }
                    Scan-Node $p.b "root"
                    if (-not $foundPopup) {
                        # Show top-level structure
                        Write-Host "  Top-level children:" -ForegroundColor Gray
                        foreach ($c in $p.b.children) {
                            $vis = if ($c.vis -eq $false) { " [HIDDEN]" } else { "" }
                            $popup = if ($c.popup) { " [POPUP]" } else { "" }
                            Write-Host "    $($c.kind) id=$($c.id) key=$($c.key) vis=$($c.vis)$vis$popup" -ForegroundColor Gray
                        }
                    }
                }
                elseif ($p.t -eq "act_result") { Write-Host "[$count] act_result: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Cyan }
                elseif ($p.t -eq "delta") { 
                    # Check delta for popup changes
                    if ($p.b -and $p.b.ops) {
                        foreach ($op in $p.b.ops) {
                            if ($op.k -and $op.k -match "popup|menu") {
                                Write-Host "[$count] delta with popup/menu change: $($op.k)" -ForegroundColor Yellow
                            }
                        }
                    }
                    Write-Host "[$count] delta" -ForegroundColor DarkGray 
                }
                elseif ($p.t -eq "scr_list_res") { Write-Host "[$count] scr_list_res" -ForegroundColor DarkGray }
                else { Write-Host "[$count] $($p.t)" -ForegroundColor Gray }
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red; break }
}

Write-Host "`nTotal: $count msgs, state=$($ws.State)" -ForegroundColor Cyan
$ws.Dispose()
