#GhoststoryAuto.ps1 - Auto Ghost Story emulator scheduler
#Manages scheduled start/stop of emulator windows
param(
    [switch]$Status,
    [switch]$Run,
    [switch]$StopAll,
    [switch]$StartAll,
    [string]$TestClient
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogDir = Join-Path $ScriptDir "logs"
$LogFile = Join-Path $LogDir "ghoststory.log"
$StatusLog = Join-Path $LogDir "status_$(Get-Date -Format 'yyyyMMdd').json"
$ReportDir = Join-Path $ScriptDir "reports"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$ts] [$Level] $Message"
    $color = switch ($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "OK"    { "Green" }
        default { "White" }
    }
    Write-Host $entry -ForegroundColor $color
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    $entry | Out-File -FilePath $LogFile -Append -Encoding UTF8
}

function Write-StatusLog {
    param([string]$Client, [string]$Action, [string]$Detail = "")
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    
    $log = @()
    if (Test-Path $StatusLog) {
        $log = Get-Content $StatusLog -Raw | ConvertFrom-Json
        if ($log -isnot [System.Collections.IEnumerable]) { $log = @($log) }
    }
    
    $entry = [PSCustomObject]@{
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        client    = $Client
        action    = $Action
        detail    = $Detail
    }
    
    $log += $entry
    $log | ConvertTo-Json -Depth 5 | Out-File -FilePath $StatusLog -Encoding UTF8
}

$MAX_CLIENTS = 10

function Get-RunningClientCount {
    $procs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
    return $procs.Count
}

function Test-CanOpenClient {
    $running = Get-RunningClientCount
    # Give buffer: allow if under limit (not at limit)
    if ($running -ge $MAX_CLIENTS) {
        Write-Log "Cannot open: $running/$MAX_CLIENTS clients (at limit)" "WARN"
        return $false
    }
    Write-Log "Can open: $running/$MAX_CLIENTS clients" "INFO"
    return $true
}

function Get-GhostStoryStatus {
    $status = @{
        title = ""
        statusText = ""
        tasks = @()
        controlPanel = @()
        activityPanel = @()
    }
    
    $proc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
    if (-not $proc) { return $status }
    
    $status.title = $proc.MainWindowTitle
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $status }
    
    # Read status bar text via UIAutomation
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
        
        # Find all text elements
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text
        )
        $textElements = $element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        
        foreach ($el in $textElements) {
            $name = $el.Current.Name
            if ($name -and $name.Length -gt 0) {
                $status.tasks += $name
            }
        }
        
        # Find control and activity panels
        $paneCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Pane
        )
        $paneElements = $element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $paneCondition)
        
        foreach ($pane in $paneElements) {
            $paneName = $pane.Current.Name
            if ($paneName -match "KHIEN|DIEU") {
                $childTexts = $pane.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
                foreach ($child in $childTexts) {
                    $childName = $child.Current.Name
                    if ($childName -and $childName.Length -gt 0) {
                        $status.controlPanel += $childName
                    }
                }
            }
            if ($paneName -match "DONG|HOAT") {
                $childTexts = $pane.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
                foreach ($child in $childTexts) {
                    $childName = $child.Current.Name
                    if ($childName -and $childName.Length -gt 0) {
                        $status.activityPanel += $childName
                    }
                }
            }
        }
    } catch {}
    
    return $status
}

function Read-Config {
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Config not found: $ConfigPath" "ERROR"
        exit 1
    }
    return Get-Content $ConfigPath -Raw | ConvertFrom-Json
}

function Save-Config {
    param($Config)
    $Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $ConfigPath -Encoding UTF8
}

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

function Get-AllEmulators {
    $procs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
    $result = @()
    foreach ($p in $procs) {
        $title = $p.MainWindowTitle
        $client = ""
        if ($title -match "\(client_(\d+)\)") {
            $client = "client_$($Matches[1])"
        }
        $result += [PSCustomObject]@{
            PID     = $p.Id
            Client  = $client
            Title   = $title
            Running = $true
        }
    }
    return $result
}

function Close-GhostStoryTab {
    param([string]$ClientName)
    
    $gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
    if (-not $gsProc) { return $false }
    
    $hwnd = $gsProc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $false }
    
    try {
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

public class TabHelper {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
    
    public static bool ClickCloseButton(IntPtr hWnd) {
        RECT rect;
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
        return false;
    }
}
"@
        
        # Find the client window and click its X button
        $clientProc = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match $ClientName } | Select-Object -First 1
        if ($clientProc) {
            [TabHelper]::ClickCloseButton($clientProc.MainWindowHandle) | Out-Null
            Start-Sleep -Seconds 2
            return $true
        }
        return $false
    } catch {
        Write-Log "Error closing tab: $_" "ERROR"
        return $false
    }
}

function Stop-Emulator {
    param([string]$ClientName)
    $proc = Get-EmulatorProcess -ClientName $ClientName
    if ($proc) {
        try {
            $hwnd = $proc.MainWindowHandle
            
            # Click X button at top-right corner of window
            Close-GhostStoryTab -ClientName $ClientName
            Start-Sleep -Seconds 2
            
            # Check if still running, force kill
            $check = Get-EmulatorProcess -ClientName $ClientName
            if ($check) {
                $check | Stop-Process -Force
                Start-Sleep -Seconds 2
            }
            
            # Final check
            $final = Get-EmulatorProcess -ClientName $ClientName
            if (-not $final) {
                Write-Log "Stopped $ClientName (PID: $($proc.Id))" "OK"
                Write-StatusLog -Client $ClientName -Action "STOP" -Detail "PID: $($proc.Id)"
                return $true
            } else {
                Write-Log "Failed to stop $ClientName" "ERROR"
                return $false
            }
        } catch {
            Write-Log "Error stopping $ClientName : $_" "ERROR"
            return $false
        }
    } else {
        Write-Log "$ClientName not running" "WARN"
        return $true
    }
}

function Start-Emulator {
    param([string]$ClientName, $Config)
    $existing = Get-EmulatorProcess -ClientName $ClientName
    if ($existing) {
        Write-Log "$ClientName already running (PID: $($existing.Id))" "WARN"
        return $true
    }

    # Check client limit
    if (-not (Test-CanOpenClient)) {
        return $false
    }
    
    # Click on client in Auto Ghost Story to open it
    $gsProc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
    if (-not $gsProc) {
        Write-Log "Auto Ghost Story not running" "ERROR"
        return $false
    }
    
    $gsHwnd = $gsProc.MainWindowHandle
    Add-Type @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct RECT3 {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
}
public class GsClick {
    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT3 lpRect);
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);
}
"@ -ErrorAction SilentlyContinue
    
    $gsRect = New-Object RECT3
    [GsClick]::GetWindowRect($gsHwnd, [ref]$gsRect) | Out-Null
    
    Write-Log "Clicking $ClientName in Auto Ghost Story..." "INFO"
    [GsClick]::SetForegroundWindow($gsHwnd) | Out-Null
    Start-Sleep -Milliseconds 200
    
    # Find and click the client entry in the list
    $clientNum = [int]($ClientName -replace 'client_','')
    $entryIndex = $clientNum - 41  # 41=0, 42=1, 43=2, 44=3, 45=4
    
    $clickX = $gsRect.Left + 100
    $clickY = $gsRect.Top + 150 + ($entryIndex * 25)
    
    [GsClick]::SetCursorPos($clickX, $clickY) | Out-Null
    Start-Sleep -Milliseconds 100
    [GsClick]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    [GsClick]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    
    Start-Sleep -Seconds 3
    
    $newProc = Get-EmulatorProcess -ClientName $ClientName
    if ($newProc) {
        Write-Log "Started $ClientName (PID: $($newProc.Id))" "OK"
        Write-StatusLog -Client $ClientName -Action "START" -Detail "PID: $($newProc.Id)"
        return $true
    } else {
        Write-Log "Clicked but $ClientName not detected yet" "WARN"
        return $true
    }
}

function Show-Status {
    $config = Read-Config
    $emulators = Get-AllEmulators
    $runningCount = Get-RunningClientCount

    Write-Host "`n=== Auto Ghost Story - Emulator Status ===" -ForegroundColor Cyan
    Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "Clients: $runningCount / $MAX_CLIENTS" -ForegroundColor $(if ($runningCount -ge $MAX_CLIENTS) { "Red" } else { "Green" })
    Write-Host ""

    Write-Host "--- Fixed (always ON) ---" -ForegroundColor Yellow
    foreach ($e in $config.emulators.fixed) {
        $proc = $emulators | Where-Object { $_.Client -eq $e.client }
        $status = if ($proc) { "[RUNNING] PID=$($proc.PID)" } else { "[DOWN]" }
        $color = if ($proc) { "Green" } else { "Red" }
        Write-Host "  $($e.client) | $($e.name) | $status" -ForegroundColor $color
    }

    Write-Host "`n--- Scheduled (time-based) ---" -ForegroundColor Yellow
    foreach ($e in $config.emulators.scheduled) {
        $proc = $emulators | Where-Object { $_.Client -eq $e.client }
        $status = if ($proc) { "[RUNNING] PID=$($proc.PID)" } else { "[STOPPED]" }
        $color = if ($proc) { "Green" } else { "DarkGray" }
        Write-Host "  $($e.client) | $($e.name) | $status" -ForegroundColor $color
    }

    Write-Host "`n--- Schedule ---" -ForegroundColor Yellow
    $now = Get-Date
    foreach ($s in $config.schedule) {
        $marker = ""
        if ($s.time -eq $now.ToString("HH:mm")) { $marker = " <-- NOW" }
        $openList = $s.clients -join ', '
        $closeList = if ($s.close) { $s.close -join ', ' } else { "none" }
        Write-Host "  $($s.time) | OPEN: $openList | CLOSE: $closeList$marker" -ForegroundColor $(if ($marker) { "Cyan" } else { "White" })
    }
    
    # Show Auto Ghost Story status
    Write-Host "`n--- Auto Ghost Story Status ---" -ForegroundColor Yellow
    $gsStatus = Get-GhostStoryStatus
    if ($gsStatus.title) {
        Write-Host "  Window: $($gsStatus.title)" -ForegroundColor White
    }
    if ($gsStatus.tasks.Count -gt 0) {
        Write-Host "  Tasks:" -ForegroundColor Gray
        foreach ($task in $gsStatus.tasks) {
            Write-Host "    - $task" -ForegroundColor Gray
        }
    }
    
    # Show today's log
    if (Test-Path $StatusLog) {
        Write-Host "`n--- Today's Activity ---" -ForegroundColor Yellow
        $log = Get-Content $StatusLog -Raw | ConvertFrom-Json
        if ($log -is [System.Collections.IEnumerable]) {
            $recent = $log | Select-Object -Last 20
            foreach ($entry in $recent) {
                $color = switch ($entry.action) {
                    "START" { "Green" }
                    "STOP"  { "Red" }
                    default { "White" }
                }
                Write-Host "  $($entry.timestamp) | $($entry.action) | $($entry.client) | $($entry.detail)" -ForegroundColor $color
            }
        }
    }
    Write-Host ""
}

function Start-Scheduler {
    $config = Read-Config
    $executedTasks = @{}
    $lastResetDate = (Get-Date).ToString("yyyyMMdd")

    Write-Log "========================================" "INFO"
    Write-Log "  Ghoststory Auto Scheduler - Started" "INFO"
    Write-Log "========================================" "INFO"
    Write-Log "Fixed emulators: $($config.emulators.fixed.Count)" "INFO"
    Write-Log "Scheduled emulators: $($config.emulators.scheduled.Count)" "INFO"
    Write-Log "Schedule entries: $($config.schedule.Count)" "INFO"

    while ($true) {
        $now = Get-Date
        $currentTime = $now.ToString("HH:mm")
        $todayKey = $now.ToString("yyyyMMdd")
        $hour = [int]$now.ToString("HH")
        $minute = [int]$now.ToString("mm")

        # Reset after midnight (00:00 - 00:05)
        if ($todayKey -ne $lastResetDate -and $hour -eq 0 -and $minute -le 5) {
            Write-Log "========================================" "INFO"
            Write-Log "  MIDNIGHT RESET - $todayKey" "INFO"
            Write-Log "========================================" "INFO"
            
            # Reset executed tasks
            $executedTasks = @{}
            Write-Log "Reset executed tasks" "OK"
            
            # Archive yesterday's log
            $yesterdayLog = Join-Path $LogDir "status_$lastResetDate.json"
            if (Test-Path $yesterdayLog) {
                $archiveDir = Join-Path $LogDir "archive"
                if (-not (Test-Path $archiveDir)) { New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null }
                $archiveFile = Join-Path $archiveDir "status_$lastResetDate.json"
                Move-Item $yesterdayLog $archiveFile -Force
                Write-Log "Archived log: status_$lastResetDate.json" "OK"
            }
            
            # Create new status log for today
            $newStatusLog = Join-Path $LogDir "status_$todayKey.json"
            @() | ConvertTo-Json | Out-File -FilePath $newStatusLog -Encoding UTF8
            Write-Log "Created new log: status_$todayKey.json" "OK"
            
            # Update lastResetDate
            $lastResetDate = $todayKey
            
            # Generate daily report for yesterday
            $reportScript = Join-Path $ScriptDir "GenerateReport.ps1"
            if (Test-Path $reportScript) {
                Write-Log "Generating daily report..." "INFO"
                try {
                    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$reportScript`"" -WindowStyle Hidden
                    Write-Log "Daily report triggered" "OK"
                } catch {
                    Write-Log "Report error: $_" "ERROR"
                }
            }
            
            Write-Log "Reset complete!" "OK"
        }

        foreach ($entry in $config.schedule) {
            $taskKey = "$($entry.time)_$todayKey"

            if ($executedTasks.ContainsKey($taskKey)) { continue }

            if ($currentTime -eq $entry.time) {
                Write-Log "=== $($entry.time) - Executing schedule ===" "INFO"

                # Close emulators first
                if ($entry.close) {
                    foreach ($client in $entry.close) {
                        $emuConfig = $config.emulators.scheduled | Where-Object { $_.client -eq $client }
                        $name = if ($emuConfig) { $emuConfig.name } else { $client }
                        Write-Log "Closing $name ($client)..." "INFO"
                        Stop-Emulator -ClientName $client
                        Start-Sleep -Seconds 2
                    }
                }

                # Then open emulators
                if ($entry.clients) {
                    foreach ($client in $entry.clients) {
                        $emuConfig = $config.emulators.scheduled | Where-Object { $_.client -eq $client }
                        $name = if ($emuConfig) { $emuConfig.name } else { $client }
                        Write-Log "Opening $name ($client)..." "INFO"
                        Start-Emulator -ClientName $client -Config $config
                        Start-Sleep -Seconds 2
                    }
                }

                $executedTasks[$taskKey] = $true
                Write-Log "Schedule done: $($entry.time)" "OK"
            }
        }

        # Monitor fixed emulators
        foreach ($e in $config.emulators.fixed) {
            $proc = Get-EmulatorProcess -ClientName $e.client
            if (-not $proc) {
                Write-Log "Fixed emulator $($e.name) ($($e.client)) is DOWN! Restarting..." "WARN"
                Start-Emulator -ClientName $e.client -Config $config
            }
        }

        # Safety rule from config
        if ($config.safetyRule -and $config.safetyRule.enabled) {
            $rule = $config.safetyRule
            $ruleTime = $rule.afterTime
            $ruleHour = [int]$ruleTime.Split(":")[0]
            $ruleMinute = [int]$ruleTime.Split(":")[1]
            $afterRuleTime = ($hour -gt $ruleHour) -or ($hour -eq $ruleHour -and $minute -ge $ruleMinute)

            if ($afterRuleTime) {
                $missingRequired = @()
                foreach ($c in $rule.requiredClients) {
                    $proc = Get-EmulatorProcess -ClientName $c
                    if (-not $proc) { $missingRequired += $c }
                }

                if ($missingRequired.Count -gt 0) {
                    Write-Log "SAFETY: After $($ruleTime), missing: $($missingRequired -join ', ')" "WARN"

                    foreach ($c in $rule.closeClients) {
                        $proc = Get-EmulatorProcess -ClientName $c
                        if ($proc) {
                            Write-Log "SAFETY: Closing $c to free slot..." "WARN"
                            Stop-Emulator -ClientName $c
                            Start-Sleep -Seconds 2
                        }
                    }

                    foreach ($c in $missingRequired) {
                        Write-Log "SAFETY: Opening $c..." "INFO"
                        Start-Emulator -ClientName $c -Config $config
                        Start-Sleep -Seconds 2
                    }

                    Write-Log "SAFETY: Override complete!" "OK"
                    Write-StatusLog -Client "SYSTEM" -Action "SAFETY_OVERRIDE" -Detail "Missing: $($missingRequired -join ', ')"
                }
            }
        }

        Start-Sleep -Seconds 30
    }
}

function Stop-AllScheduled {
    $config = Read-Config
    Write-Host "`nStopping all scheduled emulators..." -ForegroundColor Yellow
    foreach ($e in $config.emulators.scheduled) {
        Stop-Emulator -ClientName $e.client
    }
    Write-Host "Done!" -ForegroundColor Green
}

function Start-AllScheduled {
    $config = Read-Config
    Write-Host "`nStarting all scheduled emulators..." -ForegroundColor Yellow
    foreach ($e in $config.emulators.scheduled) {
        Start-Emulator -ClientName $e.client -Config $config
    }
    Write-Host "Done!" -ForegroundColor Green
}

function Test-SingleClient {
    param([string]$ClientName)
    Write-Host "`nTesting: $ClientName" -ForegroundColor Cyan
    $proc = Get-EmulatorProcess -ClientName $ClientName
    if ($proc) {
        Write-Host "Found: PID=$($proc.Id)" -ForegroundColor Green
        Write-Host "Stopping..."
        Stop-Emulator -ClientName $ClientName
        Start-Sleep -Seconds 3
        Write-Host "Starting..."
        $config = Read-Config
        Start-Emulator -ClientName $ClientName -Config $config
    } else {
        Write-Host "Not found!" -ForegroundColor Red
    }
}

# --- MAIN ---
if ($Status) {
    Show-Status
    exit 0
}

if ($StopAll) {
    Stop-AllScheduled
    exit 0
}

if ($StartAll) {
    Start-AllScheduled
    exit 0
}

if ($TestClient) {
    Test-SingleClient -ClientName $TestClient
    exit 0
}

if ($Run) {
    Start-Scheduler
    exit 0
}

# Default: show status
Show-Status
