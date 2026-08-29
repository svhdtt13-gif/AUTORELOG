#SearchJSXFunction.ps1 - Extract full X function
$js = Get-Content 'C:\Users\ADMIN\.local\share\opencode\tool-output\tool_041f8201f001uHExGEeqP3XF14' -Raw

# Find the X function definition
$idx = $js.IndexOf('function X(t,e)')
if ($idx -ge 0) {
    Write-Host "Found 'function X(t,e)' at index $idx" -ForegroundColor Green
    # Get 3000 chars starting from a bit before
    $start = [Math]::Max(0, $idx - 50)
    $len = [Math]::Min(4000, $js.Length - $start)
    Write-Host $js.Substring($start, $len) -ForegroundColor Gray
} else {
    # Try alternative signatures
    $idx = $js.IndexOf('kr=new Map')
    if ($idx -ge 0) {
        Write-Host "Found 'kr=new Map' at index $idx" -ForegroundColor Green
        $start = [Math]::Max(0, $idx - 100)
        $len = [Math]::Min(5000, $js.Length - $start)
        Write-Host $js.Substring($start, $len) -ForegroundColor Gray
    } else {
        Write-Host "Not found" -ForegroundColor Red
    }
}