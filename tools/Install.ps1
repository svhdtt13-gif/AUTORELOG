#Install.ps1 - Register auto-start on Windows login + daily report
param([switch]$Silent)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot
$LauncherScript = Join-Path $ScriptDir "GhoststoryAuto.ps1"
$ReportScript = Join-Path $ScriptDir "GenerateReport.ps1"
$TaskNameScheduler = "GhoststoryAutoScheduler"
$TaskNameReport = "GhoststoryDailyReport"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Ghoststory Auto - Install ===" -ForegroundColor Cyan

# Task 1: Scheduler (start on login)
$existing = Get-ScheduledTask -TaskName $TaskNameScheduler -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskNameScheduler -Confirm:$false
    Write-Host "[OK] Removed existing scheduler task" -ForegroundColor Yellow
}

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LauncherScript`" -Run"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $TaskNameScheduler -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Auto Ghost Story Emulator Scheduler" -Force | Out-Null
Write-Host "[OK] Scheduler task registered!" -ForegroundColor Green

# Task 2: Daily report at midnight
$existingReport = Get-ScheduledTask -TaskName $TaskNameReport -ErrorAction SilentlyContinue
if ($existingReport) {
    Unregister-ScheduledTask -TaskName $TaskNameReport -Confirm:$false
    Write-Host "[OK] Removed existing report task" -ForegroundColor Yellow
}

$actionReport = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ReportScript`""
$triggerReport = New-ScheduledTaskTrigger -Daily -At "00:05"
$settingsReport = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName $TaskNameReport -Action $actionReport -Trigger $triggerReport -Settings $settingsReport -Principal $principal -Description "Auto Ghost Story Daily Report" -Force | Out-Null
Write-Host "[OK] Daily report task registered (runs at 00:05)!" -ForegroundColor Green

if (-not $Silent) {
    $start = Read-Host "Start scheduler now? (Y/N)"
    if ($start -eq "Y" -or $start -eq "y") {
        Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$LauncherScript`" -Run" -WindowStyle Hidden
        Write-Host "[OK] Scheduler started!" -ForegroundColor Green
    }
    
    $testReport = Read-Host "Generate test report now? (Y/N)"
    if ($testReport -eq "Y" -or $testReport -eq "y") {
        powershell.exe -ExecutionPolicy Bypass -File $ReportScript
    }
}

Write-Host "`n=== Install Complete ===" -ForegroundColor Green
Write-Host "  Scheduler: starts on login" -ForegroundColor Gray
Write-Host "  Report: runs daily at 00:05" -ForegroundColor Gray
Write-Host "  Reports saved to: tools\reports\" -ForegroundColor Gray
Write-Host "  Remove: Run Uninstall.ps1 as Admin" -ForegroundColor Gray
