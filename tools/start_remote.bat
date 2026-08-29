@echo off
cd /d "C:\Users\ADMIN\Documents\ai tool\tools"
REM Start local HTTP server for db.html
start "" /min powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "serve.ps1"
timeout /t 3 >nul
REM Start ngrok tunnel to public URL
start "" /min ngrok http 8080
