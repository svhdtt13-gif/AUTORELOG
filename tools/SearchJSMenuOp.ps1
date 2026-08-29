#SearchJSMenuOp.ps1 - Find how popup/menu items are clicked (op for items)
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== op: used with menu items ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '.{0,120}op:["''](menu|item|click|check|sel|action|menu_item|button)[`'"].{0,120}')
Write-Host "Count: $($m.Count)"
foreach ($x in $m[0..10]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== Th table ops keys (op handlers) ===" -ForegroundColor Cyan
$m2 = [regex]::Matches($js, '.{0,60}(toggle|row_toggle|cell_click|menu|check_item|click):\{apply.{0,120}')
Write-Host "Count: $($m2.Count)"
foreach ($x in $m2[0..10]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== context menu rendering (menupopup/Cr) ===" -ForegroundColor Cyan
$m3 = [regex]::Matches($js, '.{0,200}(Popup|popup).{0,120}(align|contextmenu|menu_corner).{0,200}')
Write-Host "Count: $($m3.Count)"
foreach ($x in $m3[0..6]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }
Write-Host "`n"

Write-Host "=== check_item / list ops ===" -ForegroundColor Cyan
$m4 = [regex]::Matches($js, '.{0,200}(check_item|list_menu|sel_item|cell_click).{0,200}')
Write-Host "Count: $($m4.Count)"
foreach ($x in $m4[0..8]) { Write-Host "  $($x.Value -replace '[\r\n]',' ')" -ForegroundColor Gray }