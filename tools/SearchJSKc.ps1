#SearchJSKc.ps1 - Find where kc() is called
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== kc( calls ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,200}kc\(.{0,200}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..8]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== onCatalog / roster handler ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,150}(onCatalog|_roster|onRoster).{0,300}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..8]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== apps assignment ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,100}\.apps\s*=.{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }