#TestClickPositions.ps1 - Try multiple click positions on row 20 to find the menu button
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function Do-Click($posX, $posY, $label) {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    function Send-($msg) { $b = [System.Text.Encoding]::UTF8.GetBytes($msg); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
    function RecvOne { $buf = New-Object byte[] 1048576; $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { try { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(2000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } } catch { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; $ms.Dispose(); return $p }; $ms.Dispose(); return $null }
    function RecvDrain { $all = @(); while ($ws.State -eq "Open") { $buf = New-Object byte[] 1048576; try { $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $all += $p }; $ms.Dispose() } else { $ms.Dispose(); break } } catch { break } }; return $all }
    
    Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
    RecvOne | Out-Null
    Send- '{"t":"launch","product_id":73}'
    RecvOne | Out-Null
    
    # Click
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$posX; y = [int]$posY; btn = "left"; down = $true } | ConvertTo-Json -Compress
    Send- $d
    Start-Sleep -Milliseconds 80
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$posX; y = [int]$posY; btn = "left"; down = $false } | ConvertTo-Json -Compress
    Send- $u
    
    Start-Sleep -Seconds 2
    $msgs = RecvDrain
    $hasSnap = $false
    foreach ($m in $msgs) { if ($m.t -eq "snapshot") { $hasSnap = $true } }
    
    Write-Host "$label ($posX,$posY) -> state=$($ws.State) snap=$hasSnap" -ForegroundColor $(if ($hasSnap) { "Green" } else { "Gray" })
    $ws.Dispose()
}

# Row 20, visIdx=0, Y center = 3 + 9.5 = 12.5
# Try different X positions across the row
Do-Click 15 12 "Col0 checkbox"
Do-Click 70 12 "Col1 name"
Do-Click 190 12 "Col2 status"
Do-Click 250 12 "Col3 start"
Do-Click 257 12 "Col3 center"
Do-Click 265 12 "Col3 end"
Do-Click 280 12 "Col4 start"
Do-Click 310 12 "Col4 center"

# Try different Y positions too
Do-Click 257 5 "Row top"
Do-Click 257 10 "Row mid-top"
Do-Click 257 15 "Row mid"
Do-Click 257 18 "Row bottom"

Write-Host "`nDone!" -ForegroundColor Cyan
