#SearchJSCaps.ps1 - Find caps message format and owner session info
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== {t: caps } message ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,150}["'']t["'']:["'']caps["'']?.{0,200}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..4]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== scr_list / launch ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,100}(scr_list|launch|scr_start).{0,150}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..8]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }

Write-Host "`n=== instance / capacity / control requests ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,80}(instance_control|instance_stop|instance_start|batch|request_control|ctl).{0,120}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }