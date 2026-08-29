#MeasureCoords.ps1 - Show cursor position relative to Auto Ghost Story window
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCoord {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
$rect = New-Object WinCoord+RECT
[WinCoord]::GetWindowRect($hwnd, [ref]$rect) | Out-Null

Write-Host "=== MEASURE COORDINATES ===" -ForegroundColor Cyan
Write-Host "Auto Ghost Story: Left=$($rect.Left) Top=$($rect.Top) Right=$($rect.Right) Bottom=$($rect.Bottom)" -ForegroundColor Gray
Write-Host "Move mouse over checkbox, press ENTER to log, ESC to quit" -ForegroundColor Yellow
Write-Host ""

while ($true) {
    $pt = New-Object WinCoord+POINT
    [WinCoord]::GetCursorPos([ref]$pt) | Out-Null
    $relX = $pt.X - $rect.Left
    $relY = $pt.Y - $rect.Top
    
    Write-Host "`rAbs($($pt.X), $($pt.Y))  Rel($relX, $relY)  " -NoNewline -ForegroundColor White
    
    # Check for Enter key (VK_RETURN = 0x0D)
    $key = [System.Console]::KeyAvailable
    if ($key) {
        $k = [System.Console]::ReadKey($true)
        if ($k.Key -eq "Enter") {
            Write-Host ""
            Write-Host "  LOGGED: Abs($($pt.X), $($pt.Y)) Rel($relX, $relY)" -ForegroundColor Green
        }
        if ($k.Key -eq "Escape") {
            Write-Host ""
            Write-Host "Done." -ForegroundColor Cyan
            break
        }
    }
    
    Start-Sleep -Milliseconds 50
}
