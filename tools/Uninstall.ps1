#Uninstall.ps1 - Remove auto-start and daily report tasks
param([switch]$Silent)

$ErrorActionPreference = "Stop"
$TaskNameScheduler = "GhoststoryAutoScheduler"
$TaskNameReport = "GhoststoryDailyReport"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] Run as Administrator!" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Ghoststory Auto - Uninstall ===" -ForegroundColor Cyan

# Remove scheduler task
$existing = Get-ScheduledTask -TaskName $TaskNameScheduler -ErrorAction SilentlyContinue
if ($existing) {
    Unregister-ScheduledTask -TaskName $TaskNameScheduler -Confirm:$false
    Write-Host "[OK] Scheduler task removed" -ForegroundColor Green
} else {
    Write-Host "[WARN] Scheduler task not found" -ForegroundColor Yellow
}

# Remove report task
$existingReport = Get-ScheduledTask -TaskName $TaskNameReport -ErrorAction SilentlyContinue
if ($existingReport) {
    Unregister-ScheduledTask -TaskName $TaskNameReport -Confirm:$false
    Write-Host "[OK] Report task removed" -ForegroundColor Green
} else {
    Write-Host "[WARN] Report task not found" -ForegroundColor Yellow
}

if (-not $Silent) {
    $kill = Read-Host "Kill running scheduler? (Y/N)"
    if ($kill -eq "Y" -or $kill -eq "y") {
        Get-Process -Name "powershell" -ErrorAction SilentlyContinue | Where-Object {
            try { $_.CommandLine -like "*GhoststoryAuto*" } catch { $false }
        } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Killed scheduler" -ForegroundColor Green
    }
}

Write-Host "`nDone!" -ForegroundColor Green
