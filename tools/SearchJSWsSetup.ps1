#SearchJSWsSetup.ps1 - Find WebSocket connect sequence in JS
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== Ht function (send wrapper) ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, 'function Ht\(.{0,300}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== WebSocket creation ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,150}new WebSocket.{0,200}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== guid/room/ws URL ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,100}function \w+\(t\)\{.*(room|ws|sid).{0,150}')
Write-Host "Count: $($m3.Count)"
if ($m3.Count -gt 0) { foreach ($x in $m3[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray } }

Write-Host "`n=== session URL construction (game/app rooms) ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,120}(app|game|portal|screen)[a-zA-Z]*room.{0,150}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== /ws/ endpoints ===" -ForegroundColor Cyan
$m5 = [regex]::Matches($js, '.{0,100}/ws/.{0,150}')
Write-Host "Count: $($m5.Count)"
foreach ($x in $m5[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }