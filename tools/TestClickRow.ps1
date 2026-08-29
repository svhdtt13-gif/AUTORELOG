#TestClickRow.ps1 - Click each row to find client_41
$ErrorActionPreference = "Continue"

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCR {
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
}
"@

$firstX = 903
$firstY = 303
$spacing = 22  # guessed spacing

$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh truoc: $countBefore" -ForegroundColor White

# Try clicking rows 0-20 (first checkbox at Y=303)
for ($i = 0; $i -le 20; $i++) {
    $y = $firstY + ($i * $spacing)
    Write-Host "Row $i Y=$y..." -NoNewline -ForegroundColor Gray
    
    [WinCR]::SetCursorPos($firstX, $y) | Out-Null
    Start-Sleep -Milliseconds 100
    [WinCR]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [WinCR]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    
    Start-Sleep -Seconds 3
    
    $countNow = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
    if ($countNow -gt $countBefore) {
        Write-Host " FOUND! ($countBefore -> $countNow)" -ForegroundColor Green
        $countBefore = $countNow
    } else {
        Write-Host " ($countNow)" -ForegroundColor DarkGray
    }
}

Write-Host "`nFinal: $countBefore" -ForegroundColor Cyan
