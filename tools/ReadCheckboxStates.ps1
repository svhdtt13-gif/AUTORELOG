#ReadCheckboxStates.ps1 - Read checkbox states from DIEU KHIEN panel
param()

Add-Type -AssemblyName System.Drawing

$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "checkbox_positions.json"

# Load checkbox positions
if (-not (Test-Path $ConfigPath)) {
    Write-Host "Checkbox positions not found! Run MarkCheckboxes.ps1 first." -ForegroundColor Red
    return @()
}

$checkboxes = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Get DIEU KHIEN panel position
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PanelReader {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    public static IntPtr dkPanel = IntPtr.Zero;
    public static bool FindPanel(IntPtr hWnd, IntPtr lParam) {
        if (GetDlgCtrlID(hWnd) == 129) { dkPanel = hWnd; return false; }
        return true;
    }
}
"@

$proc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $proc) { 
    Write-Host "AutoGhostStory not running!" -ForegroundColor Red
    return @() 
}

$hwnd = $proc.MainWindowHandle
[PanelReader]::dkPanel = [IntPtr]::Zero
[PanelReader]::EnumChildWindows($hwnd, [PanelReader+EnumChildProc]{ param($h,$l); [PanelReader]::FindPanel($h,$l); return $true }, [IntPtr]::Zero)

$dkPanel = [PanelReader]::dkPanel
if ($dkPanel -eq [IntPtr]::Zero) {
    Write-Host "DIEU KHIEN panel not found!" -ForegroundColor Red
    return @()
}

# Get panel position
$rect = New-Object PanelReader+RECT
[PanelReader]::GetWindowRect($dkPanel, [ref]$rect)
Write-Host "Panel: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

# Capture panel screenshot
$panelW = $rect.Right - $rect.Left
$panelH = $rect.Bottom - $rect.Top
$bmp = New-Object System.Drawing.Bitmap($panelW, $panelH)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($panelW, $panelH)))

Write-Host "Captured: ${panelW}x${panelH}"

# Analyze each checkbox
$results = @()
foreach ($cb in $checkboxes) {
    $x = [math]::Min([math]::Max($cb.x, 0), $panelW - 1)
    $y = [math]::Min([math]::Max($cb.y, 0), $panelH - 1)
    
    # Sample multiple pixels around checkbox area
    $totalBrightness = 0
    $sampleCount = 0
    $hasGreen = $false
    
    for ($dx = -3; $dx -le 3; $dx++) {
        for ($dy = -3; $dy -le 3; $dy++) {
            $sx = [math]::Min([math]::Max($x + $dx, 0), $panelW - 1)
            $sy = [math]::Min([math]::Max($y + $dy, 0), $panelH - 1)
            $pixel = $bmp.GetPixel($sx, $sy)
            $brightness = ($pixel.R + $pixel.G + $pixel.B) / 3
            $totalBrightness += $brightness
            $sampleCount++
            
            # Check if green (checked checkbox)
            if ($pixel.G -gt 100 -and $pixel.G -gt $pixel.R * 1.5 -and $pixel.G -gt $pixel.B * 1.5) {
                $hasGreen = $true
            }
        }
    }
    
    $avgBrightness = $totalBrightness / $sampleCount
    
    # Determine state
    # Checkboxes typically: 
    # - Unchecked: white/light background with dark border
    # - Checked: green/blue fill or checkmark
    $isChecked = $hasGreen -or ($avgBrightness -lt 180)
    
    $state = if ($isChecked) { "DA HOAN THANH" } else { "CHUA HOAN THANH" }
    
    $results += [PSCustomObject]@{
        name = $cb.name
        state = $state
        checked = $isChecked
        brightness = [math]::Round($avgBrightness, 1)
        hasGreen = $hasGreen
        x = $cb.x
        y = $cb.y
    }
    
    $icon = if ($isChecked) { "[X]" } else { "[ ]" }
    $color = if ($isChecked) { "Green" } else { "Yellow" }
    Write-Host "$icon $($cb.name) - Brightness=$([math]::Round($avgBrightness,1)) Green=$hasGreen" -ForegroundColor $color
}

$gfx.Dispose()
$bmp.Dispose()

return $results

# If running directly, output results
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "`n=== RESULTS ===" -ForegroundColor Cyan
    $states = Get-CheckboxStates
    foreach ($s in $states) {
        $color = if ($s.checked) { "Green" } else { "Yellow" }
        Write-Host "$($s.name): $($s.state)" -ForegroundColor $color
    }
}
