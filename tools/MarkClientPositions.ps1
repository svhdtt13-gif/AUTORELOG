#MarkClientPositions.ps1 - Click to mark client positions in Auto Ghost Story
param()

Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinMark {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool GetAsyncKeyState(int vKey);
}
"@

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    return
}

$gsRect = New-Object WinMark+RECT
[WinMark]::GetWindowRect($gsProc.MainWindowHandle, [ref]$gsRect) | Out-Null
Write-Host "Auto Ghost Story at: $($gsRect.Left),$($gsRect.Top)"

Write-Host "`n=== MARK CLIENT POSITIONS ==="
Write-Host "Click on checkbox next to each client, then press ENTER"
Write-Host "Press ESC when done"

$clients = @(
    "client_41", "client_42", "client_43", "client_44", "client_45",
    "client_31", "client_32", "client_33", "client_34", "client_35"
)

$positions = @()

foreach ($client in $clients) {
    Write-Host "`nClick checkbox for $client then press ENTER..." -ForegroundColor Yellow
    
    # Wait for Enter key
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    # Get cursor position
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class CursorPos {
    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }
}
"@
    $point = New-Object CursorPos+POINT
    [CursorPos]::GetCursorPos([ref]$point) | Out-Null
    
    # Convert to Auto Ghost Story relative coordinates
    $relX = $point.X - $gsRect.Left
    $relY = $point.Y - $gsRect.Top
    
    $positions += [PSCustomObject]@{
        Client = $client
        AbsX = $point.X
        AbsY = $point.Y
        RelX = $relX
        RelY = $relY
    }
    
    Write-Host "  $client : Abs($($point.X),$($point.Y)) Rel($relX,$relY)" -ForegroundColor Green
    
    # Check if ESC pressed
    $esc = [WinMark]::GetAsyncKeyState(0x1B)
    if ($esc -band 0x8000) { break }
}

# Save positions
$outputPath = Join-Path $PSScriptRoot "client_positions.json"
$positions | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath -Encoding UTF8
Write-Host "`nSaved to: $outputPath" -ForegroundColor Cyan
Write-Host "Positions:" -ForegroundColor Cyan
$positions | Format-Table -AutoSize