@echo off
REM MonitorActive: luôn theo dõi + chủ động mở nếu nhóm chưa mở
cd /d "C:\Users\ADMIN\Documents\ai tool\tools"
powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\ADMIN\Documents\ai tool\tools\MonitorActive.ps1"
