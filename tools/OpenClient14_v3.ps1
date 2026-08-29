#OpenClient14_v3.ps1 - Try click/toggle on checkbox
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
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300
Start-Sleep -Seconds 1

# Try different formats to toggle checkbox for row 0 (client_14)
$attempts = @(
    @{ desc="toggle op k+r"; msg=@{ t="act"; k="root/1000#0"; op="toggle"; r=0 } },
    @{ desc="click op key+epoch"; msg=@{ t="act"; key="root/1000#0"; op="click"; id="oc14_1"; epoch=33; r=0 } },
    @{ desc="toggle op key+epoch"; msg=@{ t="act"; key="root/1000#0"; op="toggle"; id="oc14_2"; epoch=33; r=0 } }
)

foreach ($a in $attempts) {
    if ($ws.State -ne "Open") { Write-Host "Connection closed!" -ForegroundColor Red; break }
    
    $msg = $a.msg | ConvertTo-Json -Compress
    Write-Host "`n[$($a.desc)] Send: $msg" -ForegroundColor Yellow
    Send- $msg
    Start-Sleep -Milliseconds 800
    
    # Quick drain
    $timeout = [DateTime]::UtcNow.AddSeconds(2)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") { 
                    Write-Host "  RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" })
                    if ($p.ok) {
                        # Check row 0 checked state
                        Write-Host "  SUCCESS! Checking status..." -ForegroundColor Green
                    }
                }
                elseif ($p.t -eq "snapshot") { 
                    $row0chk = $p.b.rows[0].checked
                    Write-Host "  snapshot: row0.checked=$row0chk" -ForegroundColor Green
                }
                else { Write-Host "  $($p.t)" -ForegroundColor DarkGray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    Write-Host "  state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
}

$ws.Dispose()
