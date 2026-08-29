#SearchJSMh.ps1 - Find mh() and Lo() room resolution
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== mh function ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,50}function mh\(.{0,800}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== function Lo ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,50}function Lo\(.{0,600}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== an.value / apps ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,150}an\.value.{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== onTap/helm/press control ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,150}(Gr\.value|room=).{0,150}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }