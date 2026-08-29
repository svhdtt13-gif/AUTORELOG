#ScrollAndClick.ps1 - Use Windows API to scroll and click client checkbox
$ErrorActionPreference = "Continue"

Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public class WinAPI {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
    [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr hwndParent, IntPtr hwndChildAfter, string lpszClass, string lpszWindow);
    [DllImport("user32.dll")] public static extern bool ScrollWindow(IntPtr hWnd, int XAmount, int YAmount, ref RECT lpRect, ref RECT lpClipRect);
    [DllImport("user32.dll")] public static extern int SendMessage(IntPtr hWnd, int Msg, int wParam, int lParam);
    
    public const int WM_VSCROLL = 0x0115;
    public const int SB_LINEDOWN = 1;
    public const int SB_PAGEDOWN = 3;
    
    public static void ScrollDown(IntPtr hWnd, int lines) {
        for (int i = 0; i < lines; i++) {
            SendMessage(hWnd, WM_VSCROLL, SB_LINEDOWN, 0);
            System.Threading.Thread.Sleep(50);
        }
    }
    
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);  // LEFTDOWN
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);  // LEFTUP
    }
}
"@

# Find AutoGhostStory
$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
Write-Host "HWND: $hwnd" -ForegroundColor Gray

# Get window rect
$rect = New-Object RECT
[WinAPI]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Write-Host "Window: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)" -ForegroundColor Gray
Write-Host "Size: $($rect.Right - $rect.Left) x $($rect.Bottom - $rect.Top)" -ForegroundColor Gray

# Count before
$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh truoc: $countBefore" -ForegroundColor White

# Bring to front
[WinAPI]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# First checkbox at (903, 303) absolute
# Window at (880, 250) - relative: (23, 53)
$firstX = 903
$firstY = 303
$spacing = 22

# Try scrolling down to find client_41
# client_41 is about 10 rows below client_1 in the list
# So we need to scroll about 5-6 pages down

Write-Host "`nScrolling down to find client_41..." -ForegroundColor Yellow

# Click on client list area first (center of left panel)
$listX = $rect.Left + 150
$listY = $rect.Top + 200
[WinAPI]::ClickAt($listX, $listY)
Start-Sleep -Milliseconds 200

# Scroll down 20 lines at a time, try clicking after each scroll
for ($scroll = 0; $scroll -lt 10; $scroll++) {
    Write-Host "`nScroll $($scroll + 1)..." -NoNewline -ForegroundColor Gray
    
    # Scroll down using mouse wheel
    [WinAPI]::SetCursorPos($listX, $listY) | Out-Null
    Start-Sleep -Milliseconds 50
    
    # Mouse wheel down (120 = one notch)
    [WinAPI]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)  # MOUSEEVENTF_WHEEL
    Start-Sleep -Milliseconds 100
    [WinAPI]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [WinAPI]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [WinAPI]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 100
    [WinAPI]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)
    
    Start-Sleep -Milliseconds 300
    
    # Try clicking first checkbox position (after scrolling)
    [WinAPI]::ClickAt($firstX, $firstY)
    Start-Sleep -Seconds 2
    
    $countNow = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
    if ($countNow -gt $countBefore) {
        Write-Host " FOUND! ($countBefore -> $countNow)" -ForegroundColor Green
        $countBefore = $countNow
    } else {
        Write-Host " ($countNow)" -ForegroundColor DarkGray
    }
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Final: $countBefore" -ForegroundColor White
