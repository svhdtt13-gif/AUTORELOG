#TestSwitch.ps1 - Test close 31-35, open 41-45
$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot

# Single combined Win32 type
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

[StructLayout(LayoutKind.Sequential)]
public struct RECT2 {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}

public class WinTab {
    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT2 lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    
    public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
    
    public static bool CloseTab(IntPtr hWnd, string clientName) {
        StringBuilder sb = new StringBuilder(256);
        GetWindowText(hWnd, sb, 256);
        string text = sb.ToString();
        if (text.Contains(clientName)) {
            RECT2 rect;
            if (GetWindowRect(hWnd, out rect)) {
                int x = rect.Right - 25;
                int y = rect.Top + 15;
                SetForegroundWindow(hWnd);
                System.Threading.Thread.Sleep(200);
                SetCursorPos(x, y);
                System.Threading.Thread.Sleep(100);
                mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
                mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
                return true;
            }
        }
        return false;
    }
    
    public static void CloseAllTabs(string clientName) {
        IntPtr gsHwnd = IntPtr.Zero;
        var procs = System.Diagnostics.Process.GetProcessesByName("AutoGhostStory");
        if (procs.Length > 0) gsHwnd = procs[0].MainWindowHandle;
        if (gsHwnd == IntPtr.Zero) return;
        
        EnumChildWindows(gsHwnd, delegate(IntPtr h, IntPtr l) { 
            CloseTab(h, clientName); 
            return true; 
        }, IntPtr.Zero);
    }
}
"@

$MAX_CLIENTS = 10

function Get-EmulatorProcess {
    param([string]$ClientName)
    $procs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        if ($p.MainWindowTitle -match $ClientName) {
            return $p
        }
    }
    return $null
}

function Stop-Client {
    param([string]$ClientName)
    $proc = Get-EmulatorProcess -ClientName $ClientName
    if ($proc) {
        $hwnd = $proc.MainWindowHandle
        $rect = New-Object RECT2
        [WinTab]::GetWindowRect($hwnd, [ref]$rect) | Out-Null
        
        # Click X button at top-right corner of window
        $xBtnX = $rect.Right - 25
        $xBtnY = $rect.Top + 15
        
        Write-Host "  Clicking X at ($xBtnX, $xBtnY)..." -ForegroundColor Gray
        [WinTab]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 200
        [WinTab]::SetCursorPos($xBtnX, $xBtnY) | Out-Null
        Start-Sleep -Milliseconds 100
        [WinTab]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
        [WinTab]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
        
        Start-Sleep -Seconds 2
        
        # Check if closed
        $check = Get-EmulatorProcess -ClientName $ClientName
        if ($check) {
            Write-Host "  [FAIL] Still running" -ForegroundColor Red
            return $false
        } else {
            Write-Host "  [OK] $ClientName closed" -ForegroundColor Green
            return $true
        }
    } else {
        Write-Host "  [SKIP] $ClientName not running" -ForegroundColor Yellow
        return $true
    }
}

function Start-Client {
    param([string]$ClientName)
    $existing = Get-EmulatorProcess -ClientName $ClientName
    if ($existing) {
        Write-Host "  [SKIP] $ClientName already running" -ForegroundColor Yellow
        return $true
    }
    
    $running = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
    if ($running -ge $MAX_CLIENTS) {
        Write-Host "  [FAIL] Limit: $running/$MAX_CLIENTS" -ForegroundColor Red
        return $false
    }
    
    # Find qnyh.exe path from existing process
    $existingProc = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $existingProc) {
        Write-Host "  [FAIL] No qnyh process found" -ForegroundColor Red
        return $false
    }
    $qnyhPath = $existingProc.Path
    
    Write-Host "  Starting $ClientName via Start-Process..." -ForegroundColor Gray
    Start-Process -FilePath $qnyhPath -ArgumentList "-clone:$ClientName" -ErrorAction SilentlyContinue
    
    Start-Sleep -Seconds 3
    
    # Verify
    $newProc = Get-EmulatorProcess -ClientName $ClientName
    if ($newProc) {
        Write-Host "  [OK] $ClientName opened (PID: $($newProc.Id))" -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [WARN] Started but not detected yet" -ForegroundColor Yellow
        return $true
    }
}

# === MAIN ===
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TEST: Close 31-35, Open 41-45" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "`nTruoc: $countBefore / $MAX_CLIENTS clients" -ForegroundColor White

# Step 1: Close 31-35
Write-Host "`n--- DONG 31-35 ---" -ForegroundColor Yellow
foreach ($client in @("client_31", "client_32", "client_33", "client_34", "client_35")) {
    Write-Host "`n$client" -ForegroundColor Cyan
    Stop-Client -ClientName $client
}

$countMid = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "`nSau khi dong: $countMid / $MAX_CLIENTS clients" -ForegroundColor White

# Step 2: Open 41-45
Write-Host "`n--- MO 41-45 ---" -ForegroundColor Yellow
foreach ($client in @("client_41", "client_42", "client_43", "client_44", "client_45")) {
    Write-Host "`n$client" -ForegroundColor Cyan
    Start-Client -ClientName $client
}

$countAfter = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "`nSau khi mo: $countAfter / $MAX_CLIENTS clients" -ForegroundColor White

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  KET QUA" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Truoc: $countBefore clients" -ForegroundColor White
Write-Host "Sau:   $countAfter clients" -ForegroundColor White
