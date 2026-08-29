#TestOpenClient2.ps1 - Minimize emulators first, then click checkbox
$ErrorActionPreference = "Continue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

[StructLayout(LayoutKind.Sequential)]
public struct RECT4 {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public class WinAPI2 {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT4 lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
    }
}
"@

Write-Host "`n=== TEST OPEN CLIENT (MINIMIZE EMULATORS FIRST) ===" -ForegroundColor Cyan

# Minimize all qnyh windows
Write-Host "Minimizing all emulator windows..." -ForegroundColor Yellow
$qnyhProcs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
foreach ($p in $qnyhProcs) {
    if ($p.MainWindowHandle -ne [IntPtr]::Zero) {
        [WinAPI2]::ShowWindow($p.MainWindowHandle, 6) | Out-Null  # SW_MINIMIZE
        Write-Host "  Minimized PID=$($p.Id)" -ForegroundColor Gray
    }
}
Start-Sleep -Milliseconds 500

# Find AutoGhostStory
$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "[FAIL] AutoGhostStory not running" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
Write-Host "AutoGhostStory HWND: $hwnd" -ForegroundColor Gray

# Check count before
$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh before: $countBefore" -ForegroundColor White

# Restore if minimized
if ([WinAPI2]::IsIconic($hwnd)) {
    [WinAPI2]::ShowWindow($hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 500
}

# Get window rect
$rect = New-Object RECT4
[WinAPI2]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Write-Host "Window: Left=$($rect.Left) Top=$($rect.Top) Right=$($rect.Right) Bottom=$($rect.Bottom)" -ForegroundColor Gray

# Bring to foreground
[WinAPI2]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

$fg = [WinAPI2]::GetForegroundWindow()
Write-Host "Foreground: $fg" -ForegroundColor Gray

# Click checkbox for client_41 (X=17, Y=259 relative to window)
$clickX = $rect.Left + 17
$clickY = $rect.Top + 259
Write-Host "`nClicking client_41 checkbox at ($clickX, $clickY)..." -ForegroundColor Yellow
[WinAPI2]::ClickAt($clickX, $clickY)

Start-Sleep -Milliseconds 500
$fg2 = [WinAPI2]::GetForegroundWindow()
Write-Host "Foreground after click: $fg2" -ForegroundColor Gray

Write-Host "Waiting 8 seconds for client to start..." -ForegroundColor Gray
Start-Sleep -Seconds 8

# Check count after
$countAfter = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh after: $countAfter" -ForegroundColor White

if ($countAfter -gt $countBefore) {
    Write-Host "[OK] Client opened!" -ForegroundColor Green
} else {
    Write-Host "[FAIL] No new client detected" -ForegroundColor Red
}

# List all qnyh
Write-Host "`nAll qnyh:" -ForegroundColor Cyan
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  PID=$($_.Id) Title='$($_.MainWindowTitle)'" -ForegroundColor Gray
}
