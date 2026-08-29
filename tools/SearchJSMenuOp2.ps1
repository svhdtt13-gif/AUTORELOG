#SearchJSMenuOp2.ps1 - ops for menu items
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

Write-Host "=== ops definitions (Th table) ===" -ForegroundColor Cyan
$m = [regex]::Matches($js, '(?s)\w+:\{apply\(t,e,n\)\{.{0,220}')
Write-Host "Count: $($m.Count)"
$i = 0
foreach ($x in $m) {
    $v = $x.Value -replace '[\r\n]', ' '
    $name = ($v -split ':\{apply')[0]
    if ($name -nomatch '^run$|function') {
        Write-Host "  OP[$name] $($v.Substring([Math]::Min($v.Length,60)))" -ForegroundColor Gray
        $i++
        if ($i -ge 30) { break }
    }
}