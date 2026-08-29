#MeasureCoordsGUI.ps1 - WinForms GUI showing cursor position relative to Auto Ghost Story
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMC {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    [System.Windows.Forms.MessageBox]::Show("Auto Ghost Story not running!", "Error")
    exit 1
}

$gsHwnd = $gsProc[0].MainWindowHandle
$gsRect = New-Object WinMC+RECT
[WinMC]::GetWindowRect($gsHwnd, [ref]$gsRect) | Out-Null

$form = New-Object System.Windows.Forms.Form
$form.Text = "Measure Coords - Auto Ghost Story"
$form.Size = New-Object System.Drawing.Size(500, 400)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "Move mouse over checkbox, positions shown below"
$lblTitle.ForeColor = [System.Drawing.Color]::White
$lblTitle.Font = New-Object System.Drawing.Font("Consolas", 10)
$lblTitle.Location = New-Object System.Drawing.Point(10, 10)
$lblTitle.Size = New-Object System.Drawing.Size(470, 20)
$form.Controls.Add($lblTitle)

$lblWindow = New-Object System.Windows.Forms.Label
$lblWindow.Text = "Window: L=$($gsRect.Left) T=$($gsRect.Top) R=$($gsRect.Right) B=$($gsRect.Bottom)"
$lblWindow.ForeColor = [System.Drawing.Color]::Gray
$lblWindow.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblWindow.Location = New-Object System.Drawing.Point(10, 35)
$lblWindow.Size = New-Object System.Drawing.Size(470, 18)
$form.Controls.Add($lblWindow)

$lblAbs = New-Object System.Windows.Forms.Label
$lblAbs.Text = "Absolute: (0, 0)"
$lblAbs.ForeColor = [System.Drawing.Color]::Yellow
$lblAbs.Font = New-Object System.Drawing.Font("Consolas", 14)
$lblAbs.Location = New-Object System.Drawing.Point(10, 65)
$lblAbs.Size = New-Object System.Drawing.Size(470, 25)
$form.Controls.Add($lblAbs)

$lblRel = New-Object System.Windows.Forms.Label
$lblRel.Text = "Relative: (0, 0)"
$lblRel.ForeColor = [System.Drawing.Color]::Cyan
$lblRel.Font = New-Object System.Drawing.Font("Consolas", 14)
$lblRel.Location = New-Object System.Drawing.Point(10, 95)
$lblRel.Size = New-Object System.Drawing.Size(470, 25)
$form.Controls.Add($lblRel)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Click = log position | ESC = close"
$lblHint.ForeColor = [System.Drawing.Color]::Green
$lblHint.Font = New-Object System.Drawing.Font("Consolas", 9)
$lblHint.Location = New-Object System.Drawing.Point(10, 130)
$lblHint.Size = New-Object System.Drawing.Size(470, 18)
$form.Controls.Add($lblHint)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 20)
$logBox.ForeColor = [System.Drawing.Color]::LightGreen
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 155)
$logBox.Size = New-Object System.Drawing.Size(470, 190)
$logBox.ReadOnly = $true
$form.Controls.Add($logBox)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 50

$clickedPositions = @()

$timer.Add_Tick({
    $pt = New-Object WinMC+POINT
    [WinMC]::GetCursorPos([ref]$pt) | Out-Null
    $relX = $pt.X - $gsRect.Left
    $relY = $pt.Y - $gsRect.Top
    $lblAbs.Text = "Absolute: ($($pt.X), $($pt.Y))"
    $lblRel.Text = "Relative: ($relX, $relY)"
})

$form.Add_MouseClick({
    $pt = New-Object WinMC+POINT
    [WinMC]::GetCursorPos([ref]$pt) | Out-Null
    $relX = $pt.X - $gsRect.Left
    $relY = $pt.Y - $gsRect.Top
    $line = "Abs($($pt.X), $($pt.Y))  Rel($relX, $relY)"
    $logBox.AppendText("$line`r`n")
})

$form.Add_KeyDown({
    if ($_.KeyCode -eq "Escape") {
        $timer.Stop()
        $form.Close()
    }
})

$form.Add_Shown({
    [WinMC]::SetForegroundWindow($gsHwnd) | Out-Null
    $timer.Start()
})

$form.Add_FormClosing({ $timer.Stop() })

[void]$form.ShowDialog()
