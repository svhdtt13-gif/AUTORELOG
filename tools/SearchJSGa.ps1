#SearchJSGa.ps1 - Find Ga() control URL and gs() init
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== gs function ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,60}function gs\(.{0,600}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== Ga function ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,60}function Ga\(.{0,800}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== disp in URL query ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,100}disp.{0,150}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== /viewer?room (relay) ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,120}viewer\?room.{0,200}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }