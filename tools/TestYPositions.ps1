#TestYPositions.ps1 - Try many Y positions to find the actual button
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

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvOne | Out-Null
Send- '{"t":"launch","product_id":73}'
RecvOne | Out-Null

# List: r=[3,3,575,133], visFrom=20, visCount=7
# Row height = 133/7 = 19
# Column 3 starts at X = 3 + 19 + 120 + 105 = 247

# The act says c:3, which is column index 3 (0-based)
# Column widths: 19, 120, 105, 26, 50, 60, 60, 60, 60

# Maybe the header takes space? Let me try with different Y offsets
# Try: no header, with 1-row header, with different header sizes

$col3X = 3 + 19 + 120 + 105  # = 247
$col3Center = $col3X + 13    # = 260

Write-Host "Col3: X=$col3X center=$col3Center" -ForegroundColor Cyan

# Test: direct click on the "..." text that should be at column 3
# The act tip is "Nhiều lựa chọn hơn" = "More choices"
# Maybe I need to double-click?

function SendClick($x, $y, $label) {
    Write-Host "Click: ($x, $y) $label" -ForegroundColor Yellow -NoNewline
    
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true } | ConvertTo-Json -Compress
    Send- $d
    Start-Sleep -Milliseconds 80
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false } | ConvertTo-Json -Compress
    Send- $u
    
    Start-Sleep -Milliseconds 500
    Write-Host " done" -ForegroundColor DarkGray
}

function SendDblClick($x, $y, $label) {
    Write-Host "DblClick: ($x, $y) $label" -ForegroundColor Yellow -NoNewline
    
    # First click
    SendClick $x $y ""
    Start-Sleep -Milliseconds 100
    # Second click  
    SendClick $x $y ""
    
    Write-Host " done" -ForegroundColor DarkGray
}

function SendRightClick($x, $y, $label) {
    Write-Host "RightClick: ($x, $y) $label" -ForegroundColor Yellow -NoNewline
    
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "right"; down = $true } | ConvertTo-Json -Compress
    Send- $d
    Start-Sleep -Milliseconds 80
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "right"; down = $false } | ConvertTo-Json -Compress
    Send- $u
    
    Write-Host " done" -ForegroundColor DarkGray
}

# Try different positions for column 3
# Without header offset: Y = 3 + 9.5 = 12.5
# With 1-row header (19px): Y = 3 + 19 + 9.5 = 31.5
# With different header sizes

Write-Host "`n--- Single click at various Y ---" -ForegroundColor Cyan
SendClick $col3Center 5 "Y=5"
SendClick $col3Center 10 "Y=10"
SendClick $col3Center 12 "Y=12 (center no header)"
SendClick $col3Center 15 "Y=15"
SendClick $col3Center 20 "Y=20"
SendClick $col3Center 25 "Y=25"
SendClick $col3Center 31 "Y=31 (with header)"
SendClick $col3Center 35 "Y=35"
SendClick $col3Center 40 "Y=40"

Write-Host "`n--- Double click ---" -ForegroundColor Cyan
SendDblClick $col3Center 12 "Y=12 dbl"
SendDblClick $col3Center 31 "Y=31 dbl"

Write-Host "`n--- Right click ---" -ForegroundColor Cyan
SendRightClick $col3Center 12 "Y=12 right"
SendRightClick $col3Center 31 "Y=31 right"

# Also try the entire row area with different X
Write-Host "`n--- Full row scan ---" -ForegroundColor Cyan
for ($x = 240; $x -le 280; $x += 5) {
    SendClick $x 12 "X=$x Y=12"
}

$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
