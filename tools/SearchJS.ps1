#SearchJS.ps1 - Search JS for checkbox/check/toggle commands
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

$terms = @('toggle','check','chk','setCheck','list_menu','menu_click','instance_start','start_instance','startClient')
foreach ($term in $terms) {
    $matches = [regex]::Matches($js, ".{0,120}$term.{0,120}")
    Write-Host "`n=== $term ($($matches.Count) matches) ===" -ForegroundColor Cyan
    $i = 0
    foreach ($m in $matches) {
        if ($i -ge 5) { break }
        $val = $m.Value -replace "`n"," " -replace "`r",""
        Write-Host "  [$i] $val" -ForegroundColor Gray
        $i++
    }
}
