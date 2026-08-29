#ResizeAuto.ps1 - Resize Auto Ghost Story window to show more clients
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinRS {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
$rect = New-Object WinRS+RECT
[WinRS]::GetWindowRect($hwnd, [ref]$rect) | Out-Null

$w = $rect.Right - $rect.Left
$h = $rect.Bottom - $rect.Top
Write-Host "Current: $($rect.Left),$($rect.Top) Size: ${w}x${h}" -ForegroundColor Gray

# Resize to be taller (height 900) to show more clients
$newH = 900
[WinRS]::SetWindowPos($hwnd, [IntPtr]::Zero, $rect.Left, $rect.Top, $w, $newH, 0x0040) | Out-Null
Start-Sleep -Milliseconds 500

[WinRS]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
$newW = $rect.Right - $rect.Left
$newH2 = $rect.Bottom - $rect.Top
Write-Host "New: $($rect.Left),$($rect.Top) Size: ${newW}x${newH2}" -ForegroundColor Green
