#OpenClient14_Local.ps1 - Move Auto Ghost Story window on-screen and click checkbox
param([int]$TargetRow = 0)

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class Win32 {
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Find AutoGhostStory window
$procs = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $procs) {
    Write-Host "AutoGhostStory not running!" -ForegroundColor Red
    exit 1
}

Write-Host "Found AutoGhostStory processes:" -ForegroundColor Green
foreach ($p in $procs) {
    $title = if ($p.MainWindowTitle) { $p.MainWindowTitle } else { "(no title)" }
    $hwnd = $p.MainWindowHandle
    $rect = New-Object Win32+RECT
    [Win32]::GetWindowRect($hwnd, [ref]$rect)
    Write-Host "  PID=$($p.Id) Title='$title' HWND=$hwnd Rect=[$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)]" -ForegroundColor Cyan
}

# Find the main dialog window
$mainHwnd = [IntPtr]::Zero
foreach ($p in $procs) {
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        $rect = New-Object Win32+RECT
        [Win32]::GetWindowRect($p.MainWindowHandle, [ref]$rect)
        $title = $p.MainWindowTitle
        if ($title -match "Auto Ghost Story" -or $rect.Left -lt -30000) {
            $mainHwnd = $p.MainWindowHandle
            Write-Host "`nMain dialog: HWND=$mainHwnd at [$($rect.Left),$($rect.Top)]" -ForegroundColor Yellow
            break
        }
    }
}

if ($mainHwnd -eq [IntPtr]::Zero) {
    # Try all windows
    $allHwnds = @()
    $callback = [Win32+EnumWindowsProc]{
        param($h, $l)
        $len = [Win32]::GetWindowTextLength($h)
        if ($len -gt 0) {
            $sb = New-Object System.Text.StringBuilder ($len + 1)
            [Win32]::GetWindowText($h, $sb, $sb.Capacity) | Out-Null
            $title = $sb.ToString()
            if ($title -match "Auto Ghost Story|AutoGhost") {
                $script:allHwnds += @{ hwnd=$h; title=$title }
            }
        }
        return $true
    }
    [Win32]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
    
    if ($allHwnds.Count -gt 0) {
        Write-Host "Found windows:" -ForegroundColor Yellow
        foreach ($w in $allHwnds) { Write-Host "  $($w.hwnd) '$($w.title)'" -ForegroundColor Cyan }
        $mainHwnd = $allHwnds[0].hwnd
    }
}

if ($mainHwnd -eq [IntPtr]::Zero) {
    Write-Host "Cannot find Auto Ghost Story window!" -ForegroundColor Red
    exit 1
}

# Move window on-screen
$rect = New-Object Win32+RECT
[Win32]::GetWindowRect($mainHwnd, [ref]$rect)
$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
Write-Host "`nMoving window from [$($rect.Left),$($rect.Top)] to [100,100]..." -ForegroundColor Yellow
[Win32]::MoveWindow($mainHwnd, 100, 100, $w, $h, $true) | Out-Null
Start-Sleep -Milliseconds 500

# Bring to front
[Win32]::SetForegroundWindow($mainHwnd) | Out-Null
Start-Sleep -Milliseconds 300

# Take screenshot
$bmp = New-Object System.Drawing.Bitmap($w, $h)
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen(100, 100, 0, 0, (New-Object System.Drawing.Size($w, $h)))
$screenshotPath = "C:\Users\ADMIN\Documents\ai tool\tools\auto_ghost_story_screen.png"
$bmp.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "Screenshot saved: $screenshotPath" -ForegroundColor Green

# Now read the new position
[Win32]::GetWindowRect($mainHwnd, [ref]$rect)
Write-Host "Window now at: [$($rect.Left),$($rect.Top),$($rect.Right),$($rect.Bottom)]" -ForegroundColor Green

Write-Host "`nScreenshot saved. Check it to find checkbox position for client_14." -ForegroundColor Cyan
