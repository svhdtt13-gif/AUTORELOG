#AnalyzeMoreButton.ps1 - Connect and analyze the list item structure
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
function RecvDrain { $all = @(); while ($ws.State -eq "Open") { $buf = New-Object byte[] 1048576; try { $ms = New-Object System.IO.MemoryStream; $more = $true; while ($more -and $ws.State -eq "Open") { $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct); if ($r.AsyncWaitHandle.WaitOne(300)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false } }; if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p) { $all += $p }; $ms.Dispose() } else { $ms.Dispose(); break } } catch { break } }; return $all }

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
RecvOne | Out-Null
Send- '{"t":"launch","product_id":73}'
RecvOne | Out-Null

# Trigger snapshot
$d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = 300; y = 70; btn = "left"; down = $true } | ConvertTo-Json -Compress
Send- $d; Start-Sleep -Milliseconds 80
$u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = 300; y = 70; btn = "left"; down = $false } | ConvertTo-Json -Compress
Send- $u
Start-Sleep -Seconds 1

$allMsgs = RecvDrain
$snapshot = $null
foreach ($m in $allMsgs) { if ($m.t -eq "snapshot") { $snapshot = $m } }

if (-not $snapshot) { Write-Host "No snapshot!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

# Save full snapshot for analysis
$snapshot | ConvertTo-Json -Depth 20 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_full_detailed.json" -Encoding UTF8
Write-Host "Saved full snapshot" -ForegroundColor Green

# Find list and first row - show EVERYTHING
$list = $snapshot.b.children | Where-Object { $_.kind -eq "list" -and $_.total -gt 10 } | Select-Object -First 1
$firstRow = $list.rows[0]

Write-Host "`n=== LIST ===" -ForegroundColor Cyan
Write-Host "r: $($list.r -join ',')"
Write-Host "cols: $($list.cols | ConvertTo-Json -Compress)"
Write-Host "visFrom: $($list.visFrom)"
Write-Host "visCount: $($list.visCount)"
Write-Host "rowCount: $($list.rowCount)"
Write-Host "checked: $($list.checked)"
Write-Host "reorder: $($list.reorder)"

Write-Host "`n=== FIRST ROW (FULL) ===" -ForegroundColor Yellow
$firstRow | ConvertTo-Json -Depth 10 | Write-Host

# Show what the act array means
Write-Host "`n=== ACT ANALYSIS ===" -ForegroundColor Magenta
Write-Host "act: $($firstRow.act | ConvertTo-Json -Depth 5)"
Write-Host "Row keys: $($firstRow.PSObject.Properties.Name -join ', ')"

$ws.Dispose()
