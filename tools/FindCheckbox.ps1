#FindCheckbox.ps1 - Use UI Automation to find and click client checkboxes
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
Write-Host "HWND: $hwnd" -ForegroundColor Gray

# Get AutomationElement
$root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
Write-Host "Root: $($root.Current.Name)" -ForegroundColor Gray

# Find all elements
Write-Host "`nAll elements:" -ForegroundColor Yellow
$all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
$i = 0
foreach ($el in $all) {
    $name = $el.Current.Name
    $ctrlType = $el.Current.ControlType.ProgrammaticName
    $bounds = $el.Current.BoundingRectangle
    Write-Host "  [$i] $ctrlType Name='$name' Bounds=$bounds" -ForegroundColor Gray
    $i++
    if ($i -ge 50) { break }
}
