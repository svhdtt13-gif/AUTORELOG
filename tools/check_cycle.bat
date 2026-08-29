@echo off
REM AutoGhostStory daily cycle check at 20:00 - write report to cache\cycle_check_<date>.txt
cd /d "C:\Users\ADMIN\Documents\ai tool\tools"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\ADMIN\Documents\ai tool\tools\CheckCycle.ps1"