#GenerateReport.ps1 - Generate daily Excel report at midnight
#Reports: client status, schedule execution, Auto Ghost Story tasks
param(
    [string]$Date  # Optional: specific date (yyyy-MM-dd), default=yesterday
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
$ConfigPath = Join-Path $ScriptDir "config.json"
$LogDir = Join-Path $ScriptDir "logs"
$ReportDir = Join-Path $ScriptDir "reports"

if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }

# Determine report date
if ($Date) {
    $reportDate = [DateTime]::Parse($Date)
} else {
    $reportDate = (Get-Date).AddDays(-1)
}
$dateStr = $reportDate.ToString("yyyyMMdd")
$displayDate = $reportDate.ToString("dd/MM/yyyy")

Write-Host "=== Generating Report for $displayDate ===" -ForegroundColor Cyan

# Load config
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

# Load status log for the day
$statusLogFile = Join-Path $LogDir "status_$dateStr.json"
$statusLog = @()
if (Test-Path $statusLogFile) {
    $raw = Get-Content $statusLogFile -Raw | ConvertFrom-Json
    if ($raw -is [System.Collections.IEnumerable]) {
        $statusLog = $raw
    } else {
        $statusLog = @($raw)
    }
    Write-Host "Loaded $($statusLog.Count) log entries" -ForegroundColor Green
} else {
    Write-Host "No status log found for $displayDate" -ForegroundColor Yellow
}

# Get current emulator status
function Get-AllEmulators {
    $procs = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue
    $result = @{}
    foreach ($p in $procs) {
        $title = $p.MainWindowTitle
        if ($title -match "\(client_(\d+)\)") {
            $client = "client_$($Matches[1])"
            $result[$client] = @{
                PID = $p.Id
                Title = $title
                Running = $true
            }
        }
    }
    return $result
}

$currentEmulators = Get-AllEmulators

# Load checkbox states from DIEU KHIEN panel
$checkboxStates = @()
$checkboxConfigPath = Join-Path $ScriptDir "checkbox_positions.json"
if (Test-Path $checkboxConfigPath) {
    $checkboxScript = Join-Path $ScriptDir "ReadCheckboxStates.ps1"
    if (Test-Path $checkboxScript) {
        $checkboxStates = & $checkboxScript -ConfigPath $checkboxConfigPath
    }
}

# Get Auto Ghost Story status
function Get-GhostStoryStatus {
    $status = @{
        title = ""
        tasks = @()
        controlPanel = @()
        activityPanel = @()
    }
    
    $proc = Get-Process -Name "AutoGhostStory" -ErrorAction SilentlyContinue
    if (-not $proc) { return $status }
    
    $status.title = $proc.MainWindowTitle
    $hwnd = $proc.MainWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { return $status }
    
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $element = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
        
        # Get all text elements
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
        
        # Find control panel (DI?U KHI?N) and activity panel (HO?T D?NG)
        $paneCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Pane
        )
        $paneElements = $element.FindAll([System.Windows.Automation.TreeScope]::Descendants, $paneCondition)
        
        foreach ($pane in $paneElements) {
            $paneName = $pane.Current.Name
            if ($paneName -match "KHIEN|DIEU") {
                # Control panel - get child text elements
                $childTexts = $pane.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
                foreach ($child in $childTexts) {
                    $childName = $child.Current.Name
                    if ($childName -and $childName.Length -gt 0) {
                        $status.controlPanel += $childName
                    }
                }
            }
            if ($paneName -match "DONG|HOAT") {
                # Activity panel - get child text elements
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

$gsStatus = Get-GhostStoryStatus

# Create Excel
Write-Host "Creating Excel report..." -ForegroundColor Yellow

try {
    $excelApp = New-Object -ComObject Excel.Application
    $excelApp.Visible = $false
    $workbook = $excelApp.Workbooks.Add()
    
    # === Sheet 1: Client Status ===
    $sheet1 = $workbook.Sheets.Item(1)
    $sheet1.Name = "Trang Thai Client"
    
    # Title
    $sheet1.Cells.Item(1, 1) = "BAO CAO TRANG THAI CLIENT - $displayDate"
    $sheet1.Cells.Item(1, 1).Font.Bold = $true
    $sheet1.Cells.Item(1, 1).Font.Size = 14
    
    # Headers
    $headers = @("STT", "Client", "Ten", "Loai", "Trang Thai Hien Tai", "PID", "So Lan Chay Lai")
    for ($i = 0; $i -lt $headers.Count; $i++) {
        $sheet1.Cells.Item(3, $i + 1) = $headers[$i]
        $sheet1.Cells.Item(3, $i + 1).Font.Bold = $true
        $sheet1.Cells.Item(3, $i + 1).Interior.ColorIndex = 15
    }
    
    # Fixed clients
    $row = 4
    $stt = 1
    foreach ($e in $config.emulators.fixed) {
        $emu = $currentEmulators[$e.client]
        $running = if ($emu) { "DANG CHAY" } else { "TAT" }
        $procId = if ($emu) { $emu.PID } else { "-" }
        
        # Count restarts from log
        $restarts = ($statusLog | Where-Object { $_.client -eq $e.client -and $_.action -eq "START" }).Count
        
        $sheet1.Cells.Item($row, 1) = $stt
        $sheet1.Cells.Item($row, 2) = $e.client
        $sheet1.Cells.Item($row, 3) = $e.name
        $sheet1.Cells.Item($row, 4) = "CO DINH"
        $sheet1.Cells.Item($row, 5) = $running
        $sheet1.Cells.Item($row, 6) = $procId
        $sheet1.Cells.Item($row, 7) = $restarts
        
        # Color code
        if ($running -eq "DANG CHAY") {
            $sheet1.Cells.Item($row, 5).Interior.ColorIndex = 4
        } else {
            $sheet1.Cells.Item($row, 5).Interior.ColorIndex = 3
        }
        
        $row++
        $stt++
    }
    
    # Scheduled clients
    foreach ($e in $config.emulators.scheduled) {
        $emu = $currentEmulators[$e.client]
        $running = if ($emu) { "DANG CHAY" } else { "TAT" }
        $procId = if ($emu) { $emu.PID } else { "-" }
        
        $starts = ($statusLog | Where-Object { $_.client -eq $e.client -and $_.action -eq "START" }).Count
        $stops = ($statusLog | Where-Object { $_.client -eq $e.client -and $_.action -eq "STOP" }).Count
        
        $sheet1.Cells.Item($row, 1) = $stt
        $sheet1.Cells.Item($row, 2) = $e.client
        $sheet1.Cells.Item($row, 3) = $e.name
        $sheet1.Cells.Item($row, 4) = "HEN GIO"
        $sheet1.Cells.Item($row, 5) = $running
        $sheet1.Cells.Item($row, 6) = $procId
        $sheet1.Cells.Item($row, 7) = "$starts lan mo / $stops lan tat"
        
        if ($running -eq "DANG CHAY") {
            $sheet1.Cells.Item($row, 5).Interior.ColorIndex = 4
        } else {
            $sheet1.Cells.Item($row, 5).Interior.ColorIndex = 3
        }
        
        $row++
        $stt++
    }
    
    # Auto-fit columns
    $sheet1.Columns.AutoFit() | Out-Null
    
    # === Sheet 2: Schedule Execution ===
    $sheet2 = $workbook.Sheets.Add()
    $sheet2.Name = "Lich Trinh"
    
    $sheet2.Cells.Item(1, 1) = "LICH TRINH THUC HIEN - $displayDate"
    $sheet2.Cells.Item(1, 1).Font.Bold = $true
    $sheet2.Cells.Item(1, 1).Font.Size = 14
    
    $headers2 = @("Thoi Gian", "Hanh Dong", "Mo Client", "Tat Client", "Trang Thai")
    for ($i = 0; $i -lt $headers2.Count; $i++) {
        $sheet2.Cells.Item(3, $i + 1) = $headers2[$i]
        $sheet2.Cells.Item(3, $i + 1).Font.Bold = $true
        $sheet2.Cells.Item(3, $i + 1).Interior.ColorIndex = 15
    }
    
    $row2 = 4
    foreach ($s in $config.schedule) {
        $openList = $s.clients -join ", "
        $closeList = if ($s.close) { $s.close -join ", " } else { "-" }
        
        # Check if this schedule was executed
        $executed = $statusLog | Where-Object {
            $_.timestamp -match $s.time -and $_.action -eq "START"
        }
        $execStatus = if ($executed) { "DA THUC HIEN" } else { "CHUA THUC HIEN" }
        
        $sheet2.Cells.Item($row2, 1) = $s.time
        $sheet2.Cells.Item($row2, 2) = "Mo/Tat"
        $sheet2.Cells.Item($row2, 3) = $openList
        $sheet2.Cells.Item($row2, 4) = $closeList
        $sheet2.Cells.Item($row2, 5) = $execStatus
        
        if ($execStatus -eq "DA THUC HIEN") {
            $sheet2.Cells.Item($row2, 5).Interior.ColorIndex = 4
        } else {
            $sheet2.Cells.Item($row2, 5).Interior.ColorIndex = 6
        }
        
        $row2++
    }
    
    $sheet2.Columns.AutoFit() | Out-Null
    
    # === Sheet 3: Activity Log ===
    $sheet3 = $workbook.Sheets.Add()
    $sheet3.Name = "Nhat Ky Hoat Dong"
    
    $sheet3.Cells.Item(1, 1) = "NHIAT KY HOAT DONG - $displayDate"
    $sheet3.Cells.Item(1, 1).Font.Bold = $true
    $sheet3.Cells.Item(1, 1).Font.Size = 14
    
    $headers3 = @("Thoi Gian", "Client", "Hanh Dong", "Chi Tiet")
    for ($i = 0; $i -lt $headers3.Count; $i++) {
        $sheet3.Cells.Item(3, $i + 1) = $headers3[$i]
        $sheet3.Cells.Item(3, $i + 1).Font.Bold = $true
        $sheet3.Cells.Item(3, $i + 1).Interior.ColorIndex = 15
    }
    
    $row3 = 4
    foreach ($entry in $statusLog) {
        $sheet3.Cells.Item($row3, 1) = $entry.timestamp
        $sheet3.Cells.Item($row3, 2) = $entry.client
        $sheet3.Cells.Item($row3, 3) = $entry.action
        $sheet3.Cells.Item($row3, 4) = $entry.detail
        
        if ($entry.action -eq "START") {
            $sheet3.Cells.Item($row3, 3).Interior.ColorIndex = 4
        } elseif ($entry.action -eq "STOP") {
            $sheet3.Cells.Item($row3, 3).Interior.ColorIndex = 3
        }
        
        $row3++
    }
    
    $sheet3.Columns.AutoFit() | Out-Null
    
    # === Sheet 4: Auto Ghost Story Status ===
    $sheet4 = $workbook.Sheets.Add()
    $sheet4.Name = "Auto Ghost Story"
    
    $sheet4.Cells.Item(1, 1) = "TRANG THAI AUTO GHOST STORY - $displayDate"
    $sheet4.Cells.Item(1, 1).Font.Bold = $true
    $sheet4.Cells.Item(1, 1).Font.Size = 14
    
    $sheet4.Cells.Item(3, 1) = "Cua So:"
    $sheet4.Cells.Item(3, 1).Font.Bold = $true
    $sheet4.Cells.Item(3, 2) = $gsStatus.title
    
    # === Section 1: Control Panel Items (from Dieu Khien checkboxes) ===
    $sheet4.Cells.Item(5, 1) = "CAC NHIEM VU TRONG MUC DIEU KHIEN:"
    $sheet4.Cells.Item(5, 1).Font.Bold = $true
    $sheet4.Cells.Item(5, 1).Font.Size = 12
    
    $headersCtrl = @("STT", "Nhiem Vu", "Trang Thai")
    for ($i = 0; $i -lt $headersCtrl.Count; $i++) {
        $sheet4.Cells.Item(6, $i + 1) = $headersCtrl[$i]
        $sheet4.Cells.Item(6, $i + 1).Font.Bold = $true
        $sheet4.Cells.Item(6, $i + 1).Interior.ColorIndex = 15
    }
    
    $row4 = 7
    $ctrlNum = 1
    
    # Use checkbox states from marked positions
    if ($checkboxStates.Count -gt 0) {
        foreach ($cb in $checkboxStates) {
            $sheet4.Cells.Item($row4, 1) = $ctrlNum
            $sheet4.Cells.Item($row4, 2) = $cb.name
            $sheet4.Cells.Item($row4, 3) = $cb.state
            
            if ($cb.checked) {
                $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 4
            } else {
                $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 3
            }
            
            $row4++
            $ctrlNum++
        }
    } else {
        # Fallback: use UIAutomation data
        $allControlItems = @()
        if ($gsStatus.controlPanel.Count -gt 0) {
            $allControlItems = $gsStatus.controlPanel
        }
        
        foreach ($ctrlItem in $allControlItems) {
            $itemStatus = "KHONG XAC DINH"
            if ($ctrlItem -match "Da xong|Hoan thanh|Xong") {
                $itemStatus = "DA HOAN THANH"
            } elseif ($ctrlItem -match "Dang lam|Dang thuc hien") {
                $itemStatus = "DANG LAM"
            } elseif ($ctrlItem -match "Dang cho|Cho xu ly") {
                $itemStatus = "DANG CHO"
            } elseif ($ctrlItem -match "Tat|Stop|Koat") {
                $itemStatus = "DA TAT"
            }
            
            $sheet4.Cells.Item($row4, 1) = $ctrlNum
            $sheet4.Cells.Item($row4, 2) = $ctrlItem
            $sheet4.Cells.Item($row4, 3) = $itemStatus
            
            switch ($itemStatus) {
                "DA HOAN THANH" { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 4 }
                "DANG LAM"      { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 6 }
                "DANG CHO"      { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 7 }
                "DA TAT"        { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 3 }
                default         { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 36 }
            }
            
            $row4++
            $ctrlNum++
        }
        
        if ($allControlItems.Count -eq 0) {
            $sheet4.Cells.Item($row4, 1) = "-"
            $sheet4.Cells.Item($row4, 2) = "Chua danh dau vi tri checkbox (chay MarkCheckboxes.ps1)"
            $row4++
        }
    }
    
    # === Section 2: Activity Panel Items (from Hoat Dong) ===
    $row4 += 1
    $sheet4.Cells.Item($row4, 1) = "CAC NHIEM VU TRONG MUC HOAT DONG:"
    $sheet4.Cells.Item($row4, 1).Font.Bold = $true
    $sheet4.Cells.Item($row4, 1).Font.Size = 12
    $row4++
    
    for ($i = 0; $i -lt $headersCtrl.Count; $i++) {
        $sheet4.Cells.Item($row4, $i + 1) = $headersCtrl[$i]
        $sheet4.Cells.Item($row4, $i + 1).Font.Bold = $true
        $sheet4.Cells.Item($row4, $i + 1).Interior.ColorIndex = 15
    }
    $row4++
    
    $actNum = 1
    if ($gsStatus.activityPanel.Count -gt 0) {
        foreach ($actItem in $gsStatus.activityPanel) {
            $itemStatus = "KHONG XAC DINH"
            if ($actItem -match "Da xong|Hoan thanh|Xong") {
                $itemStatus = "DA HOAN THANH"
            } elseif ($actItem -match "Dang lam|Dang thuc hien") {
                $itemStatus = "DANG LAM"
            } elseif ($actItem -match "Dang cho|Cho xu ly") {
                $itemStatus = "DANG CHO"
            } elseif ($actItem -match "Tat|Stop|Koat") {
                $itemStatus = "DA TAT"
            }
            
            $sheet4.Cells.Item($row4, 1) = $actNum
            $sheet4.Cells.Item($row4, 2) = $actItem
            $sheet4.Cells.Item($row4, 3) = $itemStatus
            
            switch ($itemStatus) {
                "DA HOAN THANH" { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 4 }
                "DANG LAM"      { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 6 }
                "DANG CHO"      { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 7 }
                "DA TAT"        { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 3 }
                default         { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 36 }
            }
            
            $row4++
            $actNum++
        }
    } else {
        $sheet4.Cells.Item($row4, 1) = "-"
        $sheet4.Cells.Item($row4, 2) = "Khong co du lieu"
        $row4++
    }
    
    # === Section 3: Config Activities Tracking ===
    $row4 += 1
    $sheet4.Cells.Item($row4, 1) = "THEO DOI HOAT DONG (CONFIG):"
    $sheet4.Cells.Item($row4, 1).Font.Bold = $true
    $sheet4.Cells.Item($row4, 1).Font.Size = 12
    $row4++
    
    $headersAct = @("STT", "Hoat Dong", "Xuat Hien", "Trang Thai", "Thoi Diem")
    for ($i = 0; $i -lt $headersAct.Count; $i++) {
        $sheet4.Cells.Item($row4, $i + 1) = $headersAct[$i]
        $sheet4.Cells.Item($row4, $i + 1).Font.Bold = $true
        $sheet4.Cells.Item($row4, $i + 1).Interior.ColorIndex = 15
    }
    $row4++
    
    $configActNum = 1
    $activities = $config.activities
    if ($activities) {
        foreach ($activity in $activities) {
            $found = $false
            $foundTime = "-"
            $taskStatus = "CHUA XUAT HIEN"
            
            # Check in all panels
            foreach ($task in $gsStatus.tasks) {
                if ($task -match $activity) { $found = $true; break }
            }
            foreach ($ctrlItem in $gsStatus.controlPanel) {
                if ($ctrlItem -match $activity) {
                    $found = $true
                    if ($ctrlItem -match "Da xong|Hoan thanh|Xong") { $taskStatus = "DA HOAN THANH" }
                    elseif ($ctrlItem -match "Dang lam") { $taskStatus = "DANG LAM" }
                    elseif ($ctrlItem -match "Dang cho") { $taskStatus = "DANG CHO" }
                    break
                }
            }
            foreach ($actItem in $gsStatus.activityPanel) {
                if ($actItem -match $activity) {
                    $found = $true
                    if ($actItem -match "Da xong|Hoan thanh|Xong") { $taskStatus = "DA HOAN THANH" }
                    elseif ($actItem -match "Dang lam") { $taskStatus = "DANG LAM" }
                    elseif ($actItem -match "Dang cho") { $taskStatus = "DANG CHO" }
                    break
                }
            }
            foreach ($entry in $statusLog) {
                if ($entry.detail -match $activity) {
                    $found = $true
                    $foundTime = $entry.timestamp
                    break
                }
            }
            
            $sheet4.Cells.Item($row4, 1) = $configActNum
            $sheet4.Cells.Item($row4, 2) = $activity
            $sheet4.Cells.Item($row4, 3) = $(if ($found) { "CO" } else { "KHONG" })
            $sheet4.Cells.Item($row4, 4) = $taskStatus
            $sheet4.Cells.Item($row4, 5) = $foundTime
            
            if ($found) { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 4 } else { $sheet4.Cells.Item($row4, 3).Interior.ColorIndex = 3 }
            switch ($taskStatus) {
                "DA HOAN THANH" { $sheet4.Cells.Item($row4, 4).Interior.ColorIndex = 4 }
                "DANG LAM"      { $sheet4.Cells.Item($row4, 4).Interior.ColorIndex = 6 }
                "DANG CHO"      { $sheet4.Cells.Item($row4, 4).Interior.ColorIndex = 7 }
                default         { $sheet4.Cells.Item($row4, 4).Interior.ColorIndex = 3 }
            }
            
            $row4++
            $configActNum++
        }
    }
    
    # === Section 4: Raw status bar text ===
    $row4 += 1
    $sheet4.Cells.Item($row4, 1) = "NOI DUNG THANH TRANG THAI:"
    $sheet4.Cells.Item($row4, 1).Font.Bold = $true
    $row4++
    
    foreach ($task in $gsStatus.tasks) {
        $sheet4.Cells.Item($row4, 1) = $task
        $row4++
    }
    
    $sheet4.Columns.AutoFit() | Out-Null
    
    # Save file
    $timestamp = Get-Date -Format "HHmmss"
    $reportFile = Join-Path $ReportDir "BaoCao_${dateStr}_${timestamp}.xlsx"
    $workbook.SaveAs($reportFile)
    $workbook.Close($false)
    $excelApp.Quit()
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excelApp) | Out-Null
    
    Write-Host "`nReport saved: $reportFile" -ForegroundColor Green
    Write-Host "Open? (Y/N): " -NoNewline -ForegroundColor Yellow
    $open = Read-Host
    if ($open -eq "Y" -or $open -eq "y") {
        Start-Process excel.exe $reportFile
    }
    
} catch {
    Write-Host "Error creating report: $_" -ForegroundColor Red
}
