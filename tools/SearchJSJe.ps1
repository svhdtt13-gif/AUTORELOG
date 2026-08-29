#SearchJSJe.ps1 - Find je assignments (caps response)
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== je= assignments ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,300}(je\s*=).{0,400}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..10]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== caps handling (receive) ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,150}t===["'']caps["'']|caps\s*=.{0,400}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..10]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== Tn= / epoch setter ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,120}(Pe=0,Tn=0|Tn\s*=).{0,150}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..10]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }