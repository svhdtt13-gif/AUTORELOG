#TestActMessage.ps1 - Try act message to trigger "More choices" via accessibility
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

function Send-($msg) { $b = [System.Text.Encoding]::UTF8.GetBytes($msg); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }

function TryAct($msg, $label) {
    Write-Host "`n$label" -ForegroundColor Yellow
    Write-Host "  Send: $msg" -ForegroundColor DarkGray
    Send- $msg
    Start-Sleep -Milliseconds 500
    # Try receive
    $buf = New-Object byte[] 1048576
    while ($ws.State -eq "Open") {
        try {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000) -and $r.Result.Count -gt 0) {
                $resp = [System.Text.Encoding]::UTF8.GetString($buf, 0, $r.Result.Count)
                Write-Host "  Recv: $($resp.Substring(0, [Math]::Min(300, $resp.Length)))" -ForegroundColor Cyan
            } else { break }
        } catch { Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red; break }
    }
}

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
$p = RecvOne
Send- '{"t":"launch","product_id":73}'
$p = RecvOne

Write-Host "State: $($ws.State)" -ForegroundColor Green

# Try various act message formats
# The list key is "root/1000#0", row 0 has act[0] = {tip:"Nhiều lựa chọn hơn", c:3}
# Maybe act is triggered by key + action index

# Format 1: Simple act with key and action index
TryAct '{"t":"act","k":"root/1000#0","a":0}' "act on list key, a=0"

# Format 2: Act with row specification
TryAct '{"t":"act","k":"root/1000#0","a":0,"row":0}' "act on list, a=0, row=0"

# Format 3: Act with args
TryAct '{"t":"act","k":"root/1000#0","a":0,"args":[0]}' "act on list, a=0, args=[0]"

# Format 4: Act with idx (row index in act)  
TryAct '{"t":"act","idx":0,"a":0}' "act idx=0, a=0"

# Format 5: Different format
TryAct '{"t":"act","id":1000,"a":0,"row":0}' "act id=1000, a=0, row=0"

# Format 6: With key path
TryAct '{"t":"act","k":"root/1000#0/rows/0","a":0}' "act on row key path"

# Format 7: Click on the act element directly
TryAct '{"t":"act","k":"root/1000#0","act":0,"row":0}' "act with act field"

# Format 8: Try "invoke" 
TryAct '{"t":"invoke","k":"root/1000#0","a":0,"row":0}' "invoke on list"

# Format 9: Try "cmd"
TryAct '{"t":"cmd","k":"root/1000#0","cmd":"act","a":0,"row":0}' "cmd act"

# Format 10: Try without "a" 
TryAct '{"t":"act","k":"root/1000#0","row":0}' "act on list, row=0 (no a)"

# Format 11: Try with value
TryAct '{"t":"act","k":"root/1000#0","v":0}' "act v=0"

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
