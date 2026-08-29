#ToggleRow14_v2.ps1 - row_toggle with exact JS message format
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

# Caps + launch (NO drain)
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 500

# Collect initial messages and find current epoch
$epoch = 0
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
                $epoch = $p.sepoch
                Write-Host "[snapshot] gen=$($p.gen) sepoch=$epoch" -ForegroundColor Green
                $p | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_before_toggle.json" -Encoding UTF8
                if ($p.b.rows) { Write-Host "  Row0: $($p.b.rows[0].c[1]) checked=$($p.b.rows[0].checked)" -ForegroundColor Yellow }
            }
            elseif ($p.t -eq "_presence" -or $p.t -eq "_roster") { Write-Host $p.t -ForegroundColor DarkGray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

# Now send row_toggle with EXACT format: key + id as AH:LN + epoch
Write-Host "`nSending row_toggle r=0 ..." -ForegroundColor Yellow
$chars = "abcdefghijklmnopqrstuvwxyz0123456789"
$Ah = ""
for ($i = 0; $i -lt 5; $i++) { $Ah += $chars[(Get-Random -Maximum $chars.Length)] }
$actId = $Ah + ":1"
$msg = @{ t="act"; key="root/1000#0"; op="row_toggle"; r=0; id=$actId; epoch=$epoch; holds=@(@{key="root/1000#0"; field="row:0:checked"}) } | ConvertTo-Json -Compress
Write-Host "Send: $msg" -ForegroundColor DarkGray
Send- $msg

# Collect response
Write-Host "Waiting..." -ForegroundColor Gray
$timeout2 = [DateTime]::UtcNow.AddSeconds(8)
$count = 0
while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
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
                Write-Host "[$count] ACT_RESULT: ok=$($p.ok) reason=$($p.reason) id=$($p.id)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
            }
            elseif ($p.t -eq "snapshot") {
                Write-Host "[$count] snapshot gen=$($p.gen)" -ForegroundColor Green
                if ($p.b.rows) {
                    $r0 = $p.b.rows[0]
                    Write-Host "  Row0: $($r0.c[1]) checked=$($r0.checked)" -ForegroundColor Yellow
                    if ($r0.checked -eq 1) { Write-Host "  --> CHECKBOX DANG ON! Client14 duoc mo!" -ForegroundColor Green }
                }
            }
            elseif ($p.t -eq "scr_list_res") {
                if ($p.instances) {
                    foreach ($inst in $p.instances) {
                        if ($inst.id -eq "0:client_14") { Write-Host "[$count] client_14 state=$($inst.state)" -ForegroundColor $(if ($inst.state -eq "running") { "Green" } else { "Yellow" }) }
                    }
                }
            }
            elseif ($p.t -eq "delta") { Write-Host "[$count] delta" -ForegroundColor DarkGray }
            else { Write-Host "[$count] $($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "`nFinal: $count msgs, state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()