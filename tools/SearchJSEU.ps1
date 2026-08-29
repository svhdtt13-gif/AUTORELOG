#SearchJSEU.ps1 - Find eu() URL builder and Pr() 
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== eu function ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,50}function eu\(.{0,1200}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..2]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== Pr function ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,80}(function Pr|const Pr|Pr=).{0,200}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== control/ product path ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,200}control/.{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }