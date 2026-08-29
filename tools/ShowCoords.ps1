#ShowCoords.ps1 - Small floating label showing cursor coordinates
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinSC {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$gsHwnd = $gsProc[0].MainWindowHandle
$gsRect = New-Object WinSC+RECT
[WinSC]::GetWindowRect($gsHwnd, [ref]$gsRect) | Out-Null

$label = New-Object System.Windows.Forms.Form
$label.Text = "Coords"
$label.Size = New-Object System.Drawing.Size(250, 60)
$label.StartPosition = "Manual"
$label.Location = New-Object System.Drawing.Point(100, 100)
$label.FormBorderStyle = "None"
$label.BackColor = [System.Drawing.Color]::FromArgb(0, 0, 0)
$label.Opacity = 0.9
$label.TopMost = $true
$label.ShowInTaskbar = $false

$lblText = New-Object System.Windows.Forms.Label
$lblText.ForeColor = [System.Drawing.Color]::Lime
$lblText.Font = New-Object System.Drawing.Font("Consolas", 11)
$lblText.Dock = "Fill"
$lblText.TextAlign = "MiddleCenter"
$label.Controls.Add($lblText)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30
$timer.Add_Tick({
    $pt = New-Object WinSC+POINT
    [WinSC]::GetCursorPos([ref]$pt) | Out-Null
    $rx = $pt.X - $gsRect.Left
    $ry = $pt.Y - $gsRect.Top
    $lblText.Text = "Abs($($pt.X),$($pt.Y)) Rel($rx,$ry)"
    $label.Location = New-Object System.Drawing.Point($pt.X + 20, $pt.Y + 20)
})

$label.Add_KeyDown({
    if ($_.KeyCode -eq "Escape") {
        $timer.Stop()
        $label.Close()
    }
})

$label.Add_Shown({ $timer.Start() })
$label.Add_FormClosing({ $timer.Stop() })

[void]$label.ShowDialog()
