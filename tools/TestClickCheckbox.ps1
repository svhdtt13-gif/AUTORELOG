#TestClickCheckbox.ps1 - Close extra clients, then click checkbox to open
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

public class WinAPI2 {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);
    
    public static void ClickAt(int x, int y) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(100);
        mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
    }
}
"@

# Step 1: Kill extra qnyh processes (keep only 5 fixed)
Write-Host "=== STEP 1: Close extra clients ===" -ForegroundColor Cyan
$fixed = @("client_1","client_3","client_13","client_14","client_15")
$procs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
Write-Host "Current count: $($procs.Count)" -ForegroundColor White

# Kill all qnyh processes
foreach ($p in $procs) {
    Write-Host "  Killing PID=$($p.Id)..." -NoNewline -ForegroundColor Gray
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    Write-Host " done" -ForegroundColor Gray
}
Start-Sleep -Seconds 3

$countAfter = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "After kill: $countAfter" -ForegroundColor White

# Step 2: Wait for auto-restart of fixed clients
Write-Host "`nWaiting for auto-restart of fixed clients..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

$countFixed = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "After auto-restart: $countFixed" -ForegroundColor White

# Step 3: Now click checkbox for client_41
Write-Host "`n=== STEP 2: Click client_41 checkbox ===" -ForegroundColor Cyan

$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if (-not $gsProc) {
    Write-Host "Auto Ghost Story not running!" -ForegroundColor Red
    exit 1
}

$hwnd = $gsProc[0].MainWindowHandle
$rect = New-Object RECT
[WinAPI2]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
Write-Host "Window: L=$($rect.Left) T=$($rect.Top)" -ForegroundColor Gray

[WinAPI2]::SetForegroundWindow($hwnd) | Out-Null
Start-Sleep -Milliseconds 300

# First checkbox at (903, 303) - user said this is the first one
$clickX = 903
$clickY = 303

Write-Host "Clicking at ($clickX, $clickY)..." -ForegroundColor Yellow
[WinAPI2]::ClickAt($clickX, $clickY)

Write-Host "Waiting 5 seconds..." -ForegroundColor Gray
Start-Sleep -Seconds 5

$countFinal = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "After click: $countFinal" -ForegroundColor White

if ($countFinal -gt $countFixed) {
    Write-Host "[OK] Client opened! ($countFixed -> $countFinal)" -ForegroundColor Green
} elseif ($countFinal -lt $countFixed) {
    Write-Host "[WARN] Client was closed! ($countFixed -> $countFinal)" -ForegroundColor Yellow
    Write-Host "The checkbox was already checked - clicking it UNCHECKED it" -ForegroundColor Yellow
} else {
    Write-Host "[FAIL] No change ($countFinal)" -ForegroundColor Red
}

# Show all qnyh
Write-Host "`nAll qnyh:" -ForegroundColor Cyan
Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | ForEach-Object {
    $t = $_.MainWindowTitle
    Write-Host "  PID=$($_.Id) Title=$t" -ForegroundColor Gray
}
