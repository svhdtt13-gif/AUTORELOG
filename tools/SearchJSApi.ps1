#SearchJSApi.ps1 - Search JS for API endpoints and toggle handler
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== fetch( calls ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, 'fetch\(.{0,120}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }