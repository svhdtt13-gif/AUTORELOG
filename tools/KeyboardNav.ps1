#KeyboardNav.ps1 - Use keyboard to navigate client list in Auto Ghost Story
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinKB {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, IntPtr dwExtraInfo);
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
Write-Host "Bringing to front..." -ForegroundColor Gray
[WinKB]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

Write-Host "Pressing Tab to navigate..." -ForegroundColor Yellow
[System.Windows.Forms.SendKeys]::SendWait("{TAB}")
Start-Sleep -Milliseconds 200

Write-Host "Pressing Down arrow 10 times..." -ForegroundColor Yellow
for ($i = 0; $i -lt 10; $i++) {
    [System.Windows.Forms.SendKeys]::SendWait("{DOWN}")
    Start-Sleep -Milliseconds 100
}

Write-Host "Pressing Space to toggle..." -ForegroundColor Yellow
[System.Windows.Forms.SendKeys]::SendWait(" ")
Start-Sleep -Milliseconds 200

Write-Host "Done!" -ForegroundColor Green
