#LoginRemote.ps1 - Login to remote.360auto.net and get rooms
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$identity = "svhdtt1.3@gmail.com"
$password = "Danh2000"

Write-Host "=== LOGIN ===" -ForegroundColor Cyan
$body = @{
    identity = $identity
    password = $password
} | ConvertTo-Json

try {
    $result = Invoke-RestMethod -Uri "https://remote.360auto.net/session/login" -Method Post -ContentType "application/json" -Body $body
    Write-Host "Login OK!" -ForegroundColor Green
    Write-Host "Session: $($result.session)" -ForegroundColor Gray
    Write-Host "UID: $($result.uid)" -ForegroundColor Gray
    
    # Save session
    $session = $result.session
    $uid = $result.uid
    
    # Save to file for reuse
    @{ session = $session; uid = $uid } | ConvertTo-Json | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" -Encoding UTF8
    
    # Get rooms
    Write-Host "`n=== ROOMS ===" -ForegroundColor Cyan
    $headers = @{ Authorization = "Bearer $session" }
    $rooms = Invoke-RestMethod -Uri "https://remote.360auto.net/rooms" -Method Get -Headers $headers
    $rooms | ConvertTo-Json -Depth 5 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\remote_rooms.json" -Encoding UTF8
    Write-Host "Rooms saved to remote_rooms.json" -ForegroundColor Green
    
    # Display rooms
    foreach ($room in $rooms) {
        Write-Host "  Room: $($room | ConvertTo-Json -Compress)" -ForegroundColor Gray
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
}
