#SearchJSRowToggle.ps1 - Exact row_toggle / toggle bindings in JS
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== row_toggle occurrences ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,300}row_toggle.{0,300}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== sw class (toggle render) ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,400}(class:.{0,5}sw |\\\\"sw|\\\"sw).{0,250}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== function X( definition ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,50}function X\(t,e\).{0,500}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== holds: occurrences ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,200}holds:.{0,250}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }