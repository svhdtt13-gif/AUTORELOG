#GetCursorPos.ps1 - Get cursor position relative to Auto Ghost Story and save to file
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinCP {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$gsHwnd = $gsProc[0].MainWindowHandle
$gsRect = New-Object WinCP+RECT
[WinCP]::GetWindowRect($gsHwnd, [ref]$gsRect) | Out-Null

Write-Host "Window: L=$($gsRect.Left) T=$($gsRect.Top) R=$($gsRect.Right) B=$($gsRect.Bottom)" -ForegroundColor Gray
Write-Host "" -ForegroundColor Gray

# Get cursor position 3 times with 2 second delay
for ($i = 1; $i -le 3; $i++) {
    Write-Host "Position $i - Move mouse to checkbox, waiting 2 seconds..." -ForegroundColor Yellow
    Start-Sleep -Seconds 2
    
    $pt = New-Object WinCP+POINT
    [WinCP]::GetCursorPos([ref]$pt) | Out-Null
    $relX = $pt.X - $gsRect.Left
    $relY = $pt.Y - $gsRect.Top
    
    Write-Host "  Abs($($pt.X), $($pt.Y))  Rel($relX, $relY)" -ForegroundColor Green
}

Write-Host "" -ForegroundColor Gray
Write-Host "Done. Check positions above." -ForegroundColor Cyan
