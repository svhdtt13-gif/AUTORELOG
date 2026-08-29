#TestDirectStart.ps1 - Try starting qnyh.exe directly
$ErrorActionPreference = "Continue"

$countBefore = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh truoc: $countBefore" -ForegroundColor White

# Find qnyh.exe path from existing process
$existing = Get-Process -Name "qnyh" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    $path = $existing.Path
    Write-Host "qnyh.exe path: $path" -ForegroundColor Gray
} else {
    Write-Host "No qnyh process found, searching..." -ForegroundColor Yellow
    $path = "C:\Program Files\Nox\bin\nox.exe"  # fallback
}

Write-Host "`nTrying Start-Process..." -ForegroundColor Yellow
Start-Process -FilePath $path -ArgumentList "-clone:client_41" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

$countAfter = (Get-Process -Name "qnyh" -ErrorAction SilentlyContinue).Count
Write-Host "qnyh sau: $countAfter" -ForegroundColor White

if ($countAfter -gt $countBefore) {
    Write-Host "[OK] Started!" -ForegroundColor Green
} else {
    Write-Host "[FAIL] No new process" -ForegroundColor Red
}
