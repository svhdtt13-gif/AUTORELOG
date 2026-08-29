#SearchScript.ps1 - find scr_list_res trigger and scr messages
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== scr_list_res handling ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,200}scr_list_res.{0,200}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== scr_cmd / scr: / t:'scr senders ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,120}(scr_cmd|scr_|"scr").{0,150}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..8]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== list_menu send ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,250}list_menu.{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }