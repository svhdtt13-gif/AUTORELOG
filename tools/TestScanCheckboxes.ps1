#TestScanCheckboxes.ps1 - Try clicking each checkbox position to find the right one
$ErrorActionPreference = "Continue"

Add-Type @"
using System;
using System.Runtime.InteropServices;

[StructLayout(LayoutKind.Sequential)]
public struct RECT5 {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public class WinAPI3 {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT5 lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
    }
}
"@

Write-Host "`n=== SCAN CHECKBOX POSITIONS ===" -ForegroundColor Cyan

# Minimize emulators
Write-Host "Minimizing emulators..." -ForegroundColor Yellow
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.MainWindowHandle -ne [IntPtr]::Zero) {
        [WinAPI3]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }
}
Start-Sleep -Milliseconds 500

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
$hwnd = $gsProc[0].MainWindowHandle

if ([WinAPI3]::IsIconic($hwnd)) {
    [WinAPI3]::ShowWindow($hwnd, 9) | Out-Null
    Start-Sleep -Milliseconds 500
}

$rect = New-Object RECT5
[WinAPI3]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
[WinAPI3]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

Write-Host "Window: Left=$($rect.Left) Top=$($rect.Top) Right=$($rect.Right) Bottom=$($rect.Bottom)" -ForegroundColor Gray

# Try each Y position from 43 to 350, step 22
# X=17 for checkbox
$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "Current qnyh count: $countBefore" -ForegroundColor White

$checkboxX = $rect.Left + 17

for ($y = 43; $y -le 350; $y += 22) {
    $absY = $rect.Top + $y
    Write-Host "`nTrying Y=$y (abs=$absY)..." -NoNewline -ForegroundColor Gray
    
    # Re-get foreground each time
    [WinAPI3]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 100
    
    [WinAPI3]::ClickAt($checkboxX, $absY)
    Start-Sleep -Seconds 3
    
    $countNow = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
    if ($countNow -gt $countBefore) {
        Write-Host " [FOUND! Count: $countBefore -> $countNow]" -ForegroundColor Green
        $countBefore = $countNow
        
        # Check which client opened
        Start-Sleep -Seconds 2
        Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.MainWindowTitle -match "client_(\d+)") {
                Write-Host "  Opened: client_$($Matches[1]) (PID=$($_.Id))" -ForegroundColor Green
            }
        }
    } else {
        Write-Host " [no change: $countNow]" -ForegroundColor DarkGray
    }
}

Write-Host "`n=== DONE ===" -ForegroundColor Cyan
Write-Host "Final qnyh count: $((Get-Process -Name 'qnyh' -ErrorAction SilentlyContinue).Count)" -ForegroundColor White
