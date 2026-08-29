#TestShortFormat.ps1 - Try act with short format (k instead of key)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function TryAct($actMsg, $label) {
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
    
    Write-Host "`n$label" -ForegroundColor Yellow
    Write-Host "  $actMsg" -ForegroundColor DarkGray
    
    try {
        Send- $actMsg
        Start-Sleep -Milliseconds 500
        
        $buf = New-Object byte[] 1048576
        $timeout = [DateTime]::UtcNow.AddSeconds(3)
        while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
            try {
                $ms = New-Object System.IO.MemoryStream; $more = $true
                while ($more -and $ws.State -eq "Open") {
                    $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                    if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
                }
                if ($ms.Length -gt 0) {
                    $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($p.t -eq "act_result") { Write-Host "  RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
                    elseif ($p.t -eq "snapshot") { Write-Host "  snapshot gen=$($p.gen)" -ForegroundColor Green }
                    else { Write-Host "  $($p.t)" -ForegroundColor Gray }
                    $ms.Dispose()
                } else { $ms.Dispose(); break }
            } catch { break }
        }
        Write-Host "  state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    } catch { Write-Host "  ERROR" -ForegroundColor Red }
    $ws.Dispose()
}

# Try short format with k instead of key
TryAct '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}' "short k + list_menu r=5"
TryAct '{"t":"act","k":"root/1000#0","op":"list_menu","r":-1}' "short k + list_menu r=-1"
TryAct '{"t":"act","k":"root/1000#0","op":"list_menu"}' "short k + list_menu (no r)"
TryAct '{"t":"act","k":"root/1000#0","op":"menu_open","r":5}' "short k + menu_open"
TryAct '{"t":"act","k":"root/1000#0","op":"more","r":5}' "short k + more"
TryAct '{"t":"act","k":"root/1000#0","op":"click","r":5,"c":3}' "short k + click c=3"
TryAct '{"t":"act","k":"root/1000#0","op":"click","r":5,"col":3}' "short k + click col=3"
TryAct '{"t":"act","k":"root/1000#0","op":"click","i":5}' "short k + click i=5"

Write-Host "`nDone!" -ForegroundColor Cyan
