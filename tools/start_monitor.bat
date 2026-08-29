@echo off
REM MonitorActive liên tục — kiểm tra và chủ động mở mọi 30 giây
REM Chạy riêng biệt, không chặn daemon AutoCycle
cd /d "C:\Users\ADMIN\Documents\ai tool\tools"
start "MonitorActive" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\Users\ADMIN\Documents\ai tool\tools\MonitorActive.ps1" -Continuous
