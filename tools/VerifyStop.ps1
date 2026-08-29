#VerifyStop.ps1 - Trigger stop dialog, confirm, then check client_8 status
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
$buf = New-Object byte[] 1048576

function Drain($secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
}

function Get-Snapshot {
    $timeout = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                $ms.Dispose()
                if ($p.t -eq "snapshot") { return $p }
            } else { $ms.Dispose(); return $null }
        } catch { return $null }
    }
    return $null
}

function Check-Client8($snap) {
    if (-not $snap) { return }
    function Find-C8($node) {
        if ($node.key -and $node.key -match "client_8") {
            $st = if ($node.st) { $node.st } else { "?" }
            Write-Host "  client_8: key=$($node.key) st=$st vis=$($node.vis)" -ForegroundColor $(if ($st -eq "offline" -or $node.vis -eq $false) { "Green" } else { "Yellow" })
            return
        }
        if ($node.children) { foreach ($c in $node.children) { Find-C8 $c } }
    }
    Find-C8 $snap.b
}

# Step 1: Connect + caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300
Drain 2

# Step 2: Check initial state of client_8
Write-Host "`n=== Step 1: Trigger snapshot to check client_8 ===" -ForegroundColor Cyan
Send- '{"t":"act","k":"root/1000#0","a":0}'
$snap = Get-Snapshot
if ($snap) { Check-Client8 $snap }

# Step 3: Trigger stop dialog for row 5
Write-Host "`n=== Step 2: Trigger stop dialog (list_menu r=5) ===" -ForegroundColor Cyan
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}'
Start-Sleep -Seconds 1

# Find dialog
$dialogSnap = Get-Snapshot
if ($dialogSnap) {
    Write-Host "Dialog snapshot received" -ForegroundColor Green
    # Print dialog text
    function Show-Dialog($node) {
        if ($node.popup -eq $true -and $node.kind -eq "msgbox") {
            if ($node.children) {
                foreach ($c in $node.children) {
                    if ($c.kind -eq "label" -and $c.text) { Write-Host "  DIALOG: $($c.text)" -ForegroundColor Cyan }
                }
            }
        }
        if ($node.children) { foreach ($c in $node.children) { Show-Dialog $c } }
    }
    Show-Dialog $dialogSnap.b
}

# Step 4: Click "Có" (Yes) - key popup/0/6#0
Write-Host "`n=== Step 3: Click 'Có' to confirm stop ===" -ForegroundColor Cyan
$actId = "stop_$(Get-Random)"
$clickMsg = @{ t="act"; key="popup/0/6#0"; op="click"; id=$actId; epoch=30 } | ConvertTo-Json -Compress
Write-Host "Send: $clickMsg" -ForegroundColor Yellow
Send- $clickMsg
Start-Sleep -Seconds 3

# Collect responses
Write-Host "`n=== Step 4: Check results ===" -ForegroundColor Cyan
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
            if ($p.t -eq "act_result") {
                Write-Host "[$count] ACT_RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
            }
            elseif ($p.t -eq "scr_list_res") {
                $c8 = $p.instances | Where-Object { $_.id -eq "0:client_8" }
                if ($c8) {
                    Write-Host "[$count] CLIENT_8: $($c8.name) state=$($c8.state)" -ForegroundColor $(if ($c8.state -eq "offline") { "Green" } else { "Yellow" })
                } else {
                    Write-Host "[$count] scr_list_res (no client_8)" -ForegroundColor Cyan
                }
            }
            elseif ($p.t -eq "snapshot") {
                Write-Host "[$count] snapshot gen=$($p.gen)" -ForegroundColor Green
                Check-Client8 $p
            }
            elseif ($p.t -eq "delta") {
                if ($p.b -and $p.b.ops) {
                    foreach ($op in $p.b.ops) {
                        if ($op.lines) {
                            foreach ($line in $op.lines) { Write-Host "  LOG: $($line.t)" -ForegroundColor Yellow }
                        }
                    }
                }
            }
            else { Write-Host "[$count] $($p.t)" -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "`nFinal state: $($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
