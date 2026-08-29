#SearchJSUl.ps1 - Find Ul() and node disabled/en fields
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== function Ul ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,300}function Ul\(\).{0,600}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== actres occurrences near Ul/state ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,150}actres.{0,200}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== Ul= assignments (actres setter) ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,100}Ul\s*=\s*.{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== function Re ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,200}function Re\(\).{0,400}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }