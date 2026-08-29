#OpenClient14.ps1 - Open client_14 by clicking checkbox
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

function Recv-Snapshot {
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

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300
Drain 2

# Step 1: Check client_14 status
Write-Host "=== Step 1: Check client_14 ===" -ForegroundColor Cyan
Send- '{"t":"act","k":"root/1000#0","a":0}'
$snap = Recv-Snapshot
if ($snap) {
    $row0 = $snap.b.rows[0]
    Write-Host "Row 0: $($row0.c[1]) checked=$($row0.checked) chk=$($row0.chk)" -ForegroundColor Yellow
}

# Step 2: Try list_menu r=0 to see options
Write-Host "`n=== Step 2: list_menu r=0 ===" -ForegroundColor Cyan
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":0}'
Start-Sleep -Seconds 2

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
            if ($p.t -eq "snapshot") {
                # Find popup
                function Show-Popup($node) {
                    if ($node.popup -eq $true) {
                        Write-Host "POPUP: kind=$($node.kind) key=$($node.key)" -ForegroundColor Green
                        if ($node.items) {
                            $i = 0
                            foreach ($item in $node.items) {
                                $t = if ($item.t) { $item.t } else { "?" }
                                $dis = if ($item.dis) { " [DIS]" } else { "" }
                                Write-Host "  [$i] '$t'$dis" -ForegroundColor Cyan
                                $i++
                            }
                        }
                        if ($node.children) {
                            foreach ($c in $node.children) {
                                $txt = if ($c.text) { $c.text } else { "" }
                                Write-Host "  $($c.kind) '$txt' key=$($c.key)" -ForegroundColor Cyan
                            }
                        }
                    }
                    if ($node.children) { foreach ($c in $node.children) { Show-Popup $c } }
                }
                Show-Popup $p.b
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_row0_menu.json" -Encoding UTF8
            }
            elseif ($p.t -eq "act_result") { Write-Host "act_result: ok=$($p.ok)" -ForegroundColor Cyan }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

$ws.Dispose()
