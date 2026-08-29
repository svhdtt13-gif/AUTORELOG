#ToggleRow14.ps1 - Use row_toggle to turn ON client_14
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
Write-Host "Connected" -ForegroundColor Green

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

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500
Drain 2

# Try row_toggle with key+id+epoch
Write-Host "`nSending row_toggle r=0 (client_14)..." -ForegroundColor Yellow
$msg = @{ t="act"; key="root/1000#0"; op="row_toggle"; r=0; id="rt14_$(Get-Random)"; epoch=33 } | ConvertTo-Json -Compress
Write-Host "Send: $msg" -ForegroundColor DarkGray
Send- $msg

$timeout = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "act_result") {
                Write-Host "[RESULT] ok=$($p.ok) reason=$($p.reason) epoch=$($p.epoch)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
            }
            elseif ($p.t -eq "snapshot") {
                Write-Host "[snapshot] gen=$($p.gen)" -ForegroundColor Green
                # Check row 0 status
                if ($p.b.rows -and $p.b.rows.Count -gt 0) {
                    $r0 = $p.b.rows[0]
                    Write-Host "  Row0: $($r0.c[1]) checked=$($r0.checked)" -ForegroundColor Yellow
                    if ($r0.checked -eq 1) { Write-Host "  --> CHECKBOX DA BAT! Dong y mo client14" -ForegroundColor Green }
                }
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_after_toggle.json" -Encoding UTF8
            }
            elseif ($p.t -eq "scr_list_res") {
                Write-Host "[scr_list_res] Network events" -ForegroundColor DarkGray
                foreach ($inst in $p.instances) {
                    if ($inst.id -eq "0:client_14") {
                        Write-Host "  client_14: $($inst.name) state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "running") { "Green" } else { "Yellow" })
                    }
                }
            }
            elseif ($p.t -eq "delta") {
                if ($p.b -and $p.b.ops) {
                    Write-Host "[delta] ops changed" -ForegroundColor DarkGray
                }
            }
            else { Write-Host "[$($p.t)]" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()