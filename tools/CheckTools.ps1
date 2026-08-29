#CheckTools.ps1 - Diagnostic and test tool
param(
    [switch]$Quick,
    [switch]$TestOpen,
    [switch]$TestClose
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config.json"

function Write-Check {
    param([string]$Name, [string]$Status, [string]$Detail = "")
    $icon = switch ($Status) {
        "OK"    { "[PASS]" }
        "FAIL"  { "[FAIL]" }
        "WARN"  { "[WARN]" }
        "INFO"  { "[----]" }
    }
    $color = switch ($Status) {
        "OK"    { "Green" }
        "FAIL"  { "Red" }
        "WARN"  { "Yellow" }
        "INFO"  { "Gray" }
    }
    $msg = "$icon $Name"
    if ($Detail) { $msg += " - $Detail" }
    Write-Host $msg -ForegroundColor $color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CHECK TOOLS - Diagnostic & Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# === 1. Check Config ===
Write-Host "--- CONFIG ---" -ForegroundColor Yellow
if (Test-Path $ConfigPath) {
    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
        Write-Check "Config file" "OK" "Loaded successfully"
        Write-Check "Fixed emulators" "INFO" "$($config.emulators.fixed.Count) clients"
        Write-Check "Scheduled emulators" "INFO" "$($config.emulators.scheduled.Count) clients"
        Write-Check "Schedule entries" "INFO" "$($config.schedule.Count) entries"
        Write-Check "Activities" "INFO" "$($config.activities.Count) items"
        Write-Check "Safety rule" $(if ($config.safetyRule.enabled) { "OK" } else { "WARN" }) $config.safetyRule.afterTime
    } catch {
        Write-Check "Config file" "FAIL" "Parse error: $_"
    }
} else {
    Write-Check "Config file" "FAIL" "Not found: $ConfigPath"
}

# === 2. Check Auto Ghost Story ===
Write-Host ""
Write-Host "--- AUTO GHOST STORY ---" -ForegroundColor Yellow
$gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
if ($gsProc) {
    Write-Check "Process" "OK" "Running (PID: $($gsProc.Id))"
    Write-Check "Window" "OK" $gsProc.MainWindowTitle
    
    # Check if window is responsive
    $hwnd = $gsProc.MainWindowHandle
    if ($hwnd -ne [IntPtr]::Zero) {
        Write-Check "Handle" "OK" "HWND: $hwnd"
    } else {
        Write-Check "Handle" "WARN" "No window handle"
    }
} else {
    Write-Check "Process" "FAIL" "Not running!"
}

# === 3. Check Emulators ===
Write-Host ""
Write-Host "--- EMULATORS ---" -ForegroundColor Yellow
$qnyhProcs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
Write-Check "qnyh process" $(if ($qnyhProcs) { "OK" } else { "FAIL" }) "$($qnyhProcs.Count) running"

if ($config -and $qnyhProcs) {
    # Check fixed emulators
    Write-Host ""
    Write-Host "Fixed emulators:" -ForegroundColor Gray
    foreach ($e in $config.emulators.fixed) {
        $found = $false
        foreach ($p in $qnyhProcs) {
            if ($p.MainWindowTitle -match $e.client) {
                $found = $true
                Write-Check $e.client "OK" "PID=$($p.Id) - $($e.name)"
                break
            }
        }
        if (-not $found) {
            Write-Check $e.client "FAIL" "NOT RUNNING - $($e.name)"
        }
    }
    
    # Check scheduled emulators
    Write-Host ""
    Write-Host "Scheduled emulators:" -ForegroundColor Gray
    foreach ($e in $config.emulators.scheduled) {
        $found = $false
        foreach ($p in $qnyhProcs) {
            if ($p.MainWindowTitle -match $e.client) {
                $found = $true
                Write-Check $e.client "OK" "PID=$($p.Id) - $($e.name)"
                break
            }
        }
        if (-not $found) {
            Write-Check $e.client "WARN" "NOT RUNNING - $($e.name)"
        }
    }
}

# === 4. Check Scripts ===
Write-Host ""
Write-Host "--- SCRIPTS ---" -ForegroundColor Yellow
$scripts = @(
    "GhoststoryAuto.ps1",
    "GenerateReport.ps1",
    "ReadCheckboxStates.ps1",
    "Install.ps1",
    "Uninstall.ps1"
)
foreach ($script in $scripts) {
    $path = Join-Path $ScriptDir $script
    Write-Check $script $(if (Test-Path $path) { "OK" } else { "FAIL" }) $(if (Test-Path $path) { "$([math]::Round((Get-Item $path).Length/1KB,1))KB" } else { "Not found" })
}

# === 5. Check Logs ===
Write-Host ""
Write-Host "--- LOGS ---" -ForegroundColor Yellow
$logDir = Join-Path $ScriptDir "logs"
$reportDir = Join-Path $ScriptDir "reports"
Write-Check "Logs folder" $(if (Test-Path $logDir) { "OK" } else { "WARN" }) $logDir
Write-Check "Reports folder" $(if (Test-Path $reportDir) { "OK" } else { "WARN" }) $reportDir

if (Test-Path $logDir) {
    $logFiles = Get-ChildItem $logDir -File -ErrorAction SilentlyContinue
    Write-Check "Log files" "INFO" "$($logFiles.Count) files"
}

if (Test-Path $reportDir) {
    $reportFiles = Get-ChildItem $reportDir -Filter "*.xlsx" -ErrorAction SilentlyContinue
    Write-Check "Report files" "INFO" "$($reportFiles.Count) files"
}

# === 6. Check Scheduled Tasks ===
Write-Host ""
Write-Host "--- SCHEDULED TASKS ---" -ForegroundColor Yellow
$schedulerTask = Get-ScheduledTask -TaskName "GhoststoryAutoScheduler" -ErrorAction SilentlyContinue
$reportTask = Get-ScheduledTask -TaskName "GhoststoryDailyReport" -ErrorAction SilentlyContinue
Write-Check "GhoststoryAutoScheduler" $(if ($schedulerTask) { "OK" } else { "WARN" }) $(if ($schedulerTask) { $schedulerTask.State } else { "Not registered" })
Write-Check "GhoststoryDailyReport" $(if ($reportTask) { "OK" } else { "WARN" }) $(if ($reportTask) { $reportTask.State } else { "Not registered" })

# === TEST MODE ===
if ($TestOpen -or $TestClose) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  TEST MODE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    
    if ($TestOpen) {
        Write-Host ""
        Write-Host "Testing: Open scheduled emulators..." -ForegroundColor Yellow
        
        # Get exe path from existing process
        $sampleProc = $qnyhProcs | Select-Object -First 1
        if ($sampleProc) {
            $exePath = $sampleProc.MainModule.FileName
            Write-Check "EXE path" "OK" $exePath
            
            # Try to open first 2 scheduled emulators
            $testClients = $config.emulators.scheduled | Select-Object -First 2
            foreach ($client in $testClients) {
                Write-Host "  Opening $($client.client) ($($client.name))..." -ForegroundColor Gray
                
                # Check client limit
                $currentCount = $qnyhProcs.Count
                if ($currentCount -ge 10) {
                    Write-Check $client.client "FAIL" "Cannot open: $currentCount/10 clients running (limit reached)"
                    continue
                }
                
                # Check if already running
                $existing = $false
                foreach ($p in $qnyhProcs) {
                    if ($p.MainWindowTitle -match $client.client) {
                        $existing = $true
                        Write-Check $client.client "WARN" "Already running (PID: $($p.Id))"
                        break
                    }
                }
                
                if (-not $existing) {
                    try {
                        Start-Process -FilePath $exePath -WindowStyle Normal
                        Start-Sleep -Seconds 3
                        $newProc = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match $client.client }
                        if ($newProc) {
                            Write-Check $client.client "OK" "Started (PID: $($newProc.Id))"
                        } else {
                            Write-Check $client.client "WARN" "Process started but not detected yet"
                        }
                    } catch {
                        Write-Check $client.client "FAIL" "Error: $_"
                    }
                }
            }
        } else {
            Write-Check "EXE path" "FAIL" "No qnyh process found to get exe path"
        }
    }
    
    if ($TestClose) {
        Write-Host ""
        Write-Host "Testing: Close first 2 scheduled emulators..." -ForegroundColor Yellow
        
        # Add Close-GhostStoryTab function
        Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
[StructLayout(LayoutKind.Sequential)]
public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
public class TabCloser {
    [DllImport("user32.dll")]
    public static extern bool EnumChildWindows(IntPtr hWndParent, EnumChildProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern bool GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
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
            RECT rect;
            if (GetWindowRect(hWnd, out rect)) {
                int x = rect.Right - 10;
                int y = (rect.Top + rect.Bottom) / 2;
                SetCursorPos(x, y);
                mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
                mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
                return true;
            }
        }
        return false;
    }
}
"@
        
        $testClients = $config.emulators.scheduled | Select-Object -First 2
        foreach ($client in $testClients) {
            $found = $false
            foreach ($p in $qnyhProcs) {
                if ($p.MainWindowTitle -match $client.client) {
                    $found = $true
                    Write-Host "  Closing $($client.client) (PID: $($p.Id))..." -ForegroundColor Gray
                    try {
                        # First close tab in Auto Ghost Story
                        $gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
                        if ($gsProc) {
                            [TabCloser]::EnumChildWindows($gsProc.MainWindowHandle, [TabCloser+EnumChildProc]{ param($h,$l); [TabCloser]::CloseTab($h, $client.client); return $true }, [IntPtr]::Zero) | Out-Null
                            Start-Sleep -Milliseconds 500
                        }
                        
                        # Then kill the process
                        $p | Stop-Process -Force
                        Start-Sleep -Seconds 2
                        $check = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match $client.client }
                        if (-not $check) {
                            Write-Check $client.client "OK" "Closed successfully"
                        } else {
                            Write-Check $client.client "WARN" "Process still running"
                        }
                    } catch {
                        Write-Check $client.client "FAIL" "Error: $_"
                    }
                    break
                }
            }
            if (-not $found) {
                Write-Check $client.client "INFO" "Not running"
            }
        }
    }
}

# === SUMMARY ===
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CHECK COMPLETE" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
