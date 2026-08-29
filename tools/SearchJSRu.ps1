#SearchJSRu.ps1 - Find ru() connect flow and _hello
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== ru function ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,60}function ru\(.{0,600}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== _hello handler ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,120}["'']_hello["'']?.{0,200}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== onopen sequence ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,100}onopen=.{0,400}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== control ws connect (2nd WS for control) ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,200}(openControl|Pa\(|connectControl|Gl\(|/control).{0,300}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }