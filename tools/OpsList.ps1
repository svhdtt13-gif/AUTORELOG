#OpsList.ps1 - list all op definitions in JS
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw
$m = [regex]::Matches($js, '(?s)(\w+):\{apply\(t,e,n\)\{.{0,90}')
Write-Host "Total op handlers: $($m.Count)" -ForegroundColor Green
foreach ($x in $m) {
    $v = $x.Value -replace '[\r\n]', ' '
    Write-Host "  $($v.Substring(0,[Math]::Min($v.Length,120)))" -ForegroundColor Gray
}