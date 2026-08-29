@echo off
title Auto Ghost Story - Emulator Scheduler
color 0A
echo.
echo  ============================================
echo    Auto Ghost Story - Emulator Scheduler
echo  ============================================
echo.
echo   [1] Start Scheduler (background)
echo   [2] Check Status
echo   [3] Start All Scheduled
echo   [4] Stop All Scheduled
echo   [5] Generate Report Now
echo   [6] Mark Checkbox Positions (DIEU KHIEN)
echo   [7] Check Tools - Diagnostic
echo   [8] Check Tools - Test Open 2 Clients
echo   [9] Check Tools - Test Close 2 Clients
echo   [A] Install (auto-start + daily report)
echo   [B] Uninstall
echo   [C] Exit
echo.
set /p choice="Enter (1-C): "

if "%choice%"=="1" (
    echo Starting scheduler...
    start "" powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0tools\GhoststoryAuto.ps1" -Run
    timeout /t 2 >nul
    echo Scheduler started!
    exit
)
if "%choice%"=="2" (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\GhoststoryAuto.ps1" -Status
    pause
    exit
)
if "%choice%"=="3" (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\GhoststoryAuto.ps1" -StartAll
    pause
    exit
)
if "%choice%"=="4" (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\GhoststoryAuto.ps1" -StopAll
    pause
    exit
)
if "%choice%"=="5" (
    echo Generating report...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\GenerateReport.ps1"
    pause
    exit
)
if "%choice%"=="6" (
    echo Opening checkbox marker...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\MarkCheckboxes.ps1"
    pause
    exit
)
if "%choice%"=="7" (
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\CheckTools.ps1"
    pause
    exit
)
if "%choice%"=="8" (
    echo Testing: Open 2 clients...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\CheckTools.ps1" -TestOpen
    pause
    exit
)
if "%choice%"=="9" (
    echo Testing: Close 2 clients...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\CheckTools.ps1" -TestClose
    pause
    exit
)
if /i "%choice%"=="A" (
    echo Installing...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\Install.ps1"
    pause
    exit
)
if /i "%choice%"=="B" (
    echo Uninstalling...
    powershell.exe -ExecutionPolicy Bypass -File "%~dp0tools\Uninstall.ps1"
    pause
    exit
)
if /i "%choice%"=="C" exit
echo Invalid!
timeout /t 2 >nul
