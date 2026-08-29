#MarkCheckboxes.ps1 - Click to mark checkbox positions on DIEU KHIEN panel
param()

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "checkbox_positions.json"

# Capture DIEU KHIEN panel
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Collections.Generic;

public class PanelCapture {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    
    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern int GetDlgCtrlID(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    public static IntPtr dkPanel = IntPtr.Zero;
    public static List<string> panelTexts = new List<string>();
    
    public static bool FindPanel(IntPtr hWnd, IntPtr lParam) {
        if (GetDlgCtrlID(hWnd) == 129) {
            dkPanel = hWnd;
            return false;
        }
        return true;
    }
    
    public static bool GetTexts(IntPtr hWnd, IntPtr lParam) {
        StringBuilder txt = new StringBuilder(256);
        GetWindowText(hWnd, txt, 256);
        if (txt.Length > 0) {
            panelTexts.Add(txt.ToString());
        }
        return true;
    }
}
"@

$proc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "AutoGhostStory not found!" -ForegroundColor Red
    exit 1
}

$hwnd = $proc.MainWindowHandle

# Find DIEU KHIEN panel
[PanelCapture]::dkPanel = [IntPtr]::Zero
[PanelCapture]::EnumChildWindows($hwnd, [PanelCapture+EnumChildProc]{ param($h,$l); [PanelCapture]::FindPanel($h,$l); return $true }, [IntPtr]::Zero)

$dkPanel = [PanelCapture]::dkPanel
if ($dkPanel -eq [IntPtr]::Zero) {
    Write-Host "DIEU KHIEN panel not found!" -ForegroundColor Red
    exit 1
}

# Get panel position
$rect = New-Object PanelCapture+RECT
[PanelCapture]::GetWindowRect($dkPanel, [ref]$rect)
Write-Host "DIEU KHIEN panel: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"

# Capture screenshot
$panelW = $rect.Right - $rect.Left
$panelH = $rect.Bottom - $rect.Top
$bmp = New-Object System.Drawing.Bitmap($panelW, $panelH)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($rect.Left, $rect.Top, 0, 0, (New-Object System.Drawing.Size($panelW, $panelH)))

# Save temp screenshot
$tempImg = Join-Path $env:TEMP "diekhienc_panel.png"
$bmp.Save($tempImg)
$gfx.Dispose()
$bmp.Dispose()

Write-Host "`nScreenshot captured!" -ForegroundColor Green
Write-Host "`n=== INSTRUCTIONS ===" -ForegroundColor Yellow
Write-Host "1. A window will open showing the DIEU KHIEN panel"
Write-Host "2. Click on each checkbox to mark its position"
Write-Host "3. Right-click to finish and save"
Write-Host "4. Enter a name for each checkbox when prompted"
Write-Host ""

# Create form for marking
$form = New-Object System.Windows.Forms.Form
$form.Text = "Mark Checkbox Positions - Right-click to finish"
$form.Size = New-Object System.Drawing.Size(($panelW + 50), ($panelH + 100))
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::White

$pictureBox = New-Object System.Windows.Forms.PictureBox
$pictureBox.Location = New-Object System.Drawing.Point(10, 10)
$pictureBox.Size = New-Object System.Drawing.Size($panelW, $panelH)
$pictureBox.Image = [System.Drawing.Image]::FromFile($tempImg)
$pictureBox.SizeMode = "StretchImage"
$form.Controls.Add($pictureBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, ($panelH + 15))
$statusLabel.Size = New-Object System.Drawing.Size(($panelW + 30), 20)
$statusLabel.Text = "Click on checkboxes to mark positions (0 marked)"
$form.Controls.Add($statusLabel)

$checkboxes = @()

$pictureBox.Add_MouseClick({
    param($sender, $e)
    
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        # Finish marking
        $form.Close()
        return
    }
    
    # Get position relative to panel
    $x = $e.X
    $y = $e.Y
    
    # Ask for name
    $name = [Microsoft.VisualBasic.Interaction]::InputBox(
        "Enter name for checkbox at ($x, $y):", 
        "Checkbox Name", 
        "checkbox_$($checkboxes.Count + 1)"
    )
    
    if ($name) {
        $checkboxes += [PSCustomObject]@{
            name = $name
            x = $x
            y = $y
            panelX = $rect.Left + $x
            panelY = $rect.Top + $y
        }
        
        # Draw marker
        $g = [System.Drawing.Graphics]::FromImage($pictureBox.Image)
        $g.FillEllipse([System.Drawing.Brushes]::Red, ($x - 5), ($y - 5), 10, 10)
        $g.DrawString($name, [System.Drawing.Font]::new("Arial", 8), [System.Drawing.Brushes]::Yellow, ($x + 5), ($y - 5))
        $g.Dispose()
        
        $pictureBox.Refresh()
        $statusLabel.Text = "Marked: $($checkboxes.Count) checkboxes"
        
        Write-Host "Marked: $name at ($x, $y)" -ForegroundColor Green
    }
})

# Add VisualBasic for InputBox
Add-Type -AssemblyName Microsoft.VisualBasic

$form.ShowDialog()

# Save positions
if ($checkboxes.Count -gt 0) {
    $checkboxes | ConvertTo-Json -Depth 3 | Out-File -FilePath $ConfigPath -Encoding UTF8
    Write-Host "`nSaved $($checkboxes.Count) checkbox positions to: $ConfigPath" -ForegroundColor Green
    
    # Display summary
    Write-Host "`n=== MARKED CHECKBOXES ===" -ForegroundColor Cyan
    foreach ($cb in $checkboxes) {
        Write-Host "  $($cb.name) -> Panel($($cb.x), $($cb.y)) / Screen($($cb.panelX), $($cb.panelY))"
    }
} else {
    Write-Host "No checkboxes marked!" -ForegroundColor Yellow
}

# Cleanup
Remove-Item $tempImg -Force -ErrorAction SilentlyContinue
