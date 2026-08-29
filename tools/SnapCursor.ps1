#SnapCursor.ps1 - Snap cursor position to file (run multiple times)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinSnap {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) { Write-Host "Auto Ghost Story not running!"; exit 1 }

$gsHwnd = $gsProc[0].MainWindowHandle
$gsRect = New-Object WinSnap+RECT
[WinSnap]::GetWindowRect($gsHwnd, [ref]$gsRect) | Out-Null

$pt = New-Object WinSnap+POINT
[WinSnap]::GetCursorPos([ref]$pt) | Out-Null

$relX = $pt.X - $gsRect.Left
$relY = $pt.Y - $gsRect.Top

$outFile = Join-Path $PSScriptRoot "cursor_snap.txt"
"$([DateTime]::Now.ToString('HH:mm:ss')) Abs($($pt.X),$($pt.Y)) Rel($relX,$relY)" | Out-File -FilePath $outFile -Append -Encoding UTF8

Write-Host "Saved: Abs($($pt.X),$($pt.Y)) Rel($relX,$relY)" -ForegroundColor Green
