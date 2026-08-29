#RemoteByName.ps1 - Control clients by character name
param(
    [string]$Action = "list",      # list, open, close
    [string]$Name = "",            # character name to act on
    [string[]]$Names = @()        # multiple names
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

# Connect
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()

# Send caps
$caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
$sendBuf = [System.Text.Encoding]::UTF8.GetBytes($caps)
$ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$sendBuf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()

# Receive snapshot + scr_list
$receiveBuf = New-Object byte[] 131072
$snapshot = $null
$scrList = $null
$timeout = [DateTime]::UtcNow.AddSeconds(5)

while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    try {
        $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
        if ($result.AsyncWaitHandle.WaitOne(1000) -and $result.Result.Count -gt 0) {
            $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
            try {
                $parsed = $msg | ConvertFrom-Json
                if ($parsed.t -eq "snapshot") { $snapshot = $parsed }
                if ($parsed.t -eq "scr_list_res") { $scrList = $parsed }
            } catch {}
        }
    } catch { break }
}

# Build client map from scr_list_res
$clientMap = @{}
if ($scrList -and $scrList.instances) {
    foreach ($inst in $scrList.instances) {
        $name = $inst.name.Trim()
        $clientMap[$name] = @{
            idx = $inst.idx
            id = $inst.id
            state = $inst.state
            client = ($inst.id -split ":")[1]
        }
    }
}

function Get-ClientInfo($name) {
    foreach ($key in $clientMap.Keys) {
        if ($key -like "*$name*" -or $name -like "*$key*") {
            return $clientMap[$key]
        }
    }
    return $null
}

function Click-ClientCheckbox($idx) {
    # Find client in snapshot list to get coordinates
    if ($snapshot -and $snapshot.b -and $snapshot.b.children) {
        foreach ($child in $snapshot.b.children) {
            if ($child.kind -eq "list" -and $child.items) {
                $i = 0
                foreach ($item in $child.items) {
                    if ($i -eq $idx -and $item.r) {
                        $r = $item.r
                        $clickX = $r[0] + 12
                        $clickY = $r[1] + ($r[3] / 2)
                        
                        # Send mouse down
                        $mouseDown = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($mouseDown)
                        $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
                        Start-Sleep -Milliseconds 50
                        
                        # Send mouse up
                        $mouseUp = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$clickX; y = [int]$clickY; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
                        $buf = [System.Text.Encoding]::UTF8.GetBytes($mouseUp)
                        $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
                        
                        return $true
                    }
                    $i++
                }
            }
        }
    }
    return $false
}

# Execute action
if ($Action -eq "list") {
    Write-Host "=== ALL CLIENTS ===" -ForegroundColor Cyan
    foreach ($name in ($clientMap.Keys | Sort-Object)) {
        $info = $clientMap[$name]
        $status = if ($info.state -eq "running") { "[ON]" } else { "[OFF]" }
        $color = if ($info.state -eq "running") { "Green" } else { "Red" }
        Write-Host "  $status $name ($($info.client)) idx=$($info.idx)" -ForegroundColor $color
    }
}

if ($Action -eq "open") {
    $targetNames = if ($Names.Count -gt 0) { $Names } else { @($Name) }
    foreach ($n in $targetNames) {
        $info = Get-ClientInfo $n
        if ($info) {
            if ($info.state -eq "running") {
                Write-Host "[SKIP] $n already running" -ForegroundColor Yellow
            } else {
                Write-Host "[OPEN] $n (idx=$($info.idx))..." -ForegroundColor Yellow
                if (Click-ClientCheckbox $info.idx) {
                    Write-Host "[OK] Clicked checkbox for $n" -ForegroundColor Green
                } else {
                    Write-Host "[FAIL] Could not find checkbox" -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
        } else {
            Write-Host "[NOT FOUND] $n" -ForegroundColor Red
        }
    }
}

if ($Action -eq "close") {
    $targetNames = if ($Names.Count -gt 0) { $Names } else { @($Name) }
    foreach ($n in $targetNames) {
        $info = Get-ClientInfo $n
        if ($info) {
            if ($info.state -ne "running") {
                Write-Host "[SKIP] $n already stopped" -ForegroundColor Yellow
            } else {
                Write-Host "[CLOSE] $n (idx=$($info.idx))..." -ForegroundColor Yellow
                if (Click-ClientCheckbox $info.idx) {
                    Write-Host "[OK] Clicked checkbox for $n" -ForegroundColor Green
                } else {
                    Write-Host "[FAIL] Could not find checkbox" -ForegroundColor Red
                }
                Start-Sleep -Seconds 2
            }
        } else {
            Write-Host "[NOT FOUND] $n" -ForegroundColor Red
        }
    }
}

# Cleanup
if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $ct).Wait()
}
$ws.Dispose()
