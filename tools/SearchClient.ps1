#SearchClient.ps1 - Use keyboard to search and select client in Auto Ghost Story
param(
    [string]$ClientName = "HANMI"
)

Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinSK {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
Write-Host "Auto Ghost Story HWND: $hwnd" -ForegroundColor Gray

# Bring to front
[WinSK]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

Write-Host "Searching for: $ClientName" -ForegroundColor Yellow

# Method 1: Try Ctrl+F to search
Write-Host "Trying Ctrl+F..." -ForegroundColor Gray
[WinSK]::keybd_event(0x11, 0, 0, [IntPtr]::Zero)  # Ctrl down
Start-Sleep -Milliseconds 50
[WinSK]::keybd_event(0x46, 0, 0, [IntPtr]::Zero)  # F down
Start-Sleep -Milliseconds 50
[WinSK]::keybd_event(0x46, 0, 2, [IntPtr]::Zero)  # F up
[WinSK]::keybd_event(0x11, 0, 2, [IntPtr]::Zero)  # Ctrl up
Start-Sleep -Milliseconds 500

# Type client name
Write-Host "Typing: $ClientName" -ForegroundColor Gray
[System.Windows.Forms.SendKeys]::SendWait($ClientName)
Start-Sleep -Milliseconds 500

# Press Enter to search
Write-Host "Pressing Enter..." -ForegroundColor Gray
[WinSK]::keybd_event(0x0D, 0, 0, [IntPtr]::Zero)  # Enter down
Start-Sleep -Milliseconds 50
[WinSK]::keybd_event(0x0D, 0, 2, [IntPtr]::Zero)  # Enter up
Start-Sleep -Milliseconds 500

# Press Space to toggle checkbox
Write-Host "Pressing Space..." -ForegroundColor Gray
[WinSK]::keybd_event(0x20, 0, 0, [IntPtr]::Zero)  # Space down
Start-Sleep -Milliseconds 50
[WinSK]::keybd_event(0x20, 0, 2, [IntPtr]::Zero)  # Space up
Start-Sleep -Milliseconds 200

Write-Host "Done!" -ForegroundColor Green
