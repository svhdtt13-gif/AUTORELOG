#ToggleVariants.ps1 - Try multiple row_toggle message variants
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function Test-Variant($variantName, $msg) {
    Write-Host "`n=== $variantName ===" -ForegroundColor Yellow
    
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    $buf = New-Object byte[] 1048576
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    Start-Sleep -Milliseconds 300
    Send- '{"t":"launch","product_id":73}'
    Start-Sleep -Milliseconds 500
    
    # Drain initial
    $timeout = [DateTime]::UtcNow.AddSeconds(1)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $ms.Dispose() } else { $ms.Dispose(); break }
        } catch { break }
    }
    
    Write-Host "Send: $msg" -ForegroundColor DarkGray
    Send- $msg
    
    $timeout2 = [DateTime]::UtcNow.AddSeconds(4)
    $got = $false
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") { Write-Host "  ACT_RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }); $got = $true }
                elseif ($p.t -eq "snapshot") { Write-Host "  snapshot gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor Green; $got = $true; $script:storyEpoch = $p.sepoch }
                elseif ($p.t -eq "delta") { Write-Host "  delta" -ForegroundColor DarkGray }
                else { Write-Host "  $($p.t)" -ForegroundColor Gray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    Write-Host "  state=$($ws.State) got=$got" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
    $ws.Dispose()
}

# Variant 1: key + row_toggle, no id/epoch/holds
Test-Variant "V1: key, no id/epoch" '{"t":"act","key":"root/1000#0","op":"row_toggle","r":0}'

# Variant 2: k + row_toggle
Test-Variant "V2: k, no id/epoch" '{"t":"act","k":"root/1000#0","op":"row_toggle","r":0}'

# Variant 3: key + toggle + col (maybe checkbox is cell or col 0)
Test-Variant "V3: key toggle col" '{"t":"act","key":"root/1000#0","op":"toggle","col":0,"r":0}'

# Variant 4: key + click on row cell
Test-Variant "V4: key click cell 0" '{"t":"act","key":"root/1000#0","op":"cell_click","r":0,"c":0}'

Write-Host "`nDone" -ForegroundColor Cyan