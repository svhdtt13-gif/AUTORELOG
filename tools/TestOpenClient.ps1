#TestOpenClient.ps1 - Test opening a single client via checkbox click
$ErrorActionPreference = "Continue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

[StructLayout(LayoutKind.Sequential)]
public struct RECT3 {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public class WinAPI {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT3 lpRect);
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

Write-Host "`n=== TEST OPEN CLIENT ===" -ForegroundColor Cyan

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

# Check if minimized
$isMin = [WinAPI]::IsIconic($hwnd)
Write-Host "IsIconic: $isMin" -ForegroundColor Gray

# Restore if minimized
if ($isMin) {
    Write-Host "Restoring window..." -ForegroundColor Yellow
    [WinAPI]::ShowWindow($hwnd, 9) | Out-Null  # SW_RESTORE
    Start-Sleep -Milliseconds 500
}

# Get window rect
$rect = New-Object RECT3
[WinAPI]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Write-Host "Window: Left=$($rect.Left) Top=$($rect.Top) Right=$($rect.Right) Bottom=$($rect.Bottom)" -ForegroundColor Gray
Write-Host "Size: $($rect.Right - $rect.Left) x $($rect.Bottom - $rect.Top)" -ForegroundColor Gray

# Bring to foreground
[WinAPI]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

$fg = [WinAPI]::GetForegroundWindow()
Write-Host "Foreground after SetForeground: $fg (expected: $hwnd)" -ForegroundColor Gray

# Click checkbox for client_41
# X=17, Y=259 relative to window
$clickX = $rect.Left + 17
$clickY = $rect.Top + 259
Write-Host "`nClicking client_41 checkbox at ($clickX, $clickY)..." -ForegroundColor Yellow
[WinAPI]::ClickAt($clickX, $clickY)

Write-Host "Waiting 5 seconds for client to start..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Check count after
$countAfter = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh after: $countAfter" -ForegroundColor White

# Check foreground
$fg2 = [WinAPI]::GetForegroundWindow()
Write-Host "Foreground after click: $fg2" -ForegroundColor Gray

if ($countAfter -gt $countBefore) {
    Write-Host "[OK] Client opened!" -ForegroundColor Green
} else {
    Write-Host "[WARN] No new client detected" -ForegroundColor Yellow
    
    # Try double-click
    Write-Host "Trying double-click..." -ForegroundColor Yellow
    [WinAPI]::ClickAt($clickX, $clickY)
    Start-Sleep -Milliseconds 100
    [WinAPI]::ClickAt($clickX, $clickY)
    
    Start-Sleep -Seconds 5
    $countAfter2 = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
    Write-Host "qnyh after double-click: $countAfter2" -ForegroundColor White
    
    if ($countAfter2 -gt $countBefore) {
        Write-Host "[OK] Client opened with double-click!" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Still no new client" -ForegroundColor Red
    }
}

# List all qnyh processes
Write-Host "`nAll qnyh processes:" -ForegroundColor Cyan
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  PID=$($_.Id) Title='$($_.MainWindowTitle)'" -ForegroundColor Gray
}
