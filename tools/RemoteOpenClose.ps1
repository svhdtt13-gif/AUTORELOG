#RemoteOpenClose.ps1 - Open/close clients by name via remote.360auto.net
param(
    [string]$Action = "list",
    [string[]]$Open = @(),
    [string[]]$Close = @()
)

$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

function Connect-Remote {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $ws.Options.SetRequestHeader("Authorization", "Bearer $token")
    $uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
    $ct = [System.Threading.CancellationToken]::None
    $ws.ConnectAsync($uri, $ct).Wait()
    
    # Send caps
    $caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    
    return $ws
}

function Get-Snapshot($ws) {
    $ct = [System.Threading.CancellationToken]::None
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
    
    return @{ snapshot = $snapshot; scrList = $scrList }
}

function Get-ClientStatus($scrList, $name) {
    if (-not $scrList -or -not $scrList.instances) { return $null }
    foreach ($inst in $scrList.instances) {
        if ($inst.name.Trim() -like "*$name*" -or $name -like "*$($inst.name.Trim())*") {
            return @{ idx = $inst.idx; state = $inst.state; name = $inst.name.Trim() }
        }
    }
    return $null
}

function Find-ClientInSnapshot($snapshot, $name) {
    if (-not $snapshot -or -not $snapshot.b) { return $null }
    
    # Search in the list items
    function Search-Children($children) {
        foreach ($child in $children) {
            if ($child.kind -eq "list" -and $child.items) {
                foreach ($item in $child.items) {
                    if ($item.c -and $item.c.Count -gt 1) {
                        $itemName = $item.c[1].Trim()
                        if ($itemName -like "*$name*" -or $name -like "*$itemName*") {
                            return $item
                        }
                    }
                }
            }
            if ($child.children) {
                $result = Search-Children $child.children
                if ($result) { return $result }
            }
        }
        return $null
    }
    
    return Search-Children $snapshot.b.children
}

function Click-ListItem($ws, $snapshot, $item) {
    if (-not $item -or -not $item.r) { return $false }
    
    $r = $item.r
    $clickX = [int]($r[0] + 12)
    $clickY = [int]($r[1] + ($r[3] / 2))
    
    $ct = [System.Threading.CancellationToken]::None
    
    # Mouse down
    $down = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = $clickX; y = $clickY; btn = "left"; down = $true; lgen = $snapshot.gen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($down)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    
    # Mouse up
    $up = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = $clickX; y = $clickY; btn = "left"; down = $false; lgen = $snapshot.gen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($up)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    
    return $true
}

# === MAIN ===
Write-Host "=== CONNECTING ===" -ForegroundColor Cyan
$ws = Connect-Remote
Write-Host "Connected!" -ForegroundColor Green

$data = Get-Snapshot $ws
$snapshot = $data.snapshot
$scrList = $data.scrList

if ($Action -eq "list") {
    Write-Host "`n=== ALL CLIENTS ===" -ForegroundColor Cyan
    if ($scrList -and $scrList.instances) {
        foreach ($inst in ($scrList.instances | Sort-Object idx)) {
            $st = if ($inst.state -eq "running") { "[ON]" } else { "[OFF]" }
            $cl = if ($inst.state -eq "running") { "Green" } else { "Red" }
            Write-Host ("  {0,-6} idx={1,-3} {2,-15} {3}" -f $st, $inst.idx, $inst.name.Trim(), ($inst.id -split ":")[1]) -ForegroundColor $cl
        }
    }
}

if ($Close.Count -gt 0) {
    Write-Host "`n=== CLOSING CLIENTS ===" -ForegroundColor Yellow
    foreach ($name in $Close) {
        $status = Get-ClientStatus $scrList $name
        if ($status -and $status.state -eq "running") {
            Write-Host "  Closing $name (idx=$($status.idx))..." -NoNewline -ForegroundColor Gray
            $item = Find-ClientInSnapshot $snapshot $name
            if ($item) {
                Click-ListItem $ws $snapshot $item
                Write-Host " OK" -ForegroundColor Green
            } else {
                Write-Host " NOT FOUND in snapshot" -ForegroundColor Red
            }
            Start-Sleep -Seconds 2
        } elseif ($status) {
            Write-Host "  [SKIP] $name already offline" -ForegroundColor Yellow
        } else {
            Write-Host "  [NOT FOUND] $name" -ForegroundColor Red
        }
    }
}

if ($Open.Count -gt 0) {
    Write-Host "`n=== OPENING CLIENTS ===" -ForegroundColor Yellow
    # Refresh snapshot after closes
    if ($Close.Count -gt 0) {
        Start-Sleep -Seconds 2
        $data = Get-Snapshot $ws
        $snapshot = $data.snapshot
        $scrList = $data.scrList
    }
    
    foreach ($name in $Open) {
        $status = Get-ClientStatus $scrList $name
        if ($status -and $status.state -eq "running") {
            Write-Host "  [SKIP] $name already running" -ForegroundColor Yellow
        } elseif ($status) {
            Write-Host "  Opening $name (idx=$($status.idx))..." -NoNewline -ForegroundColor Gray
            $item = Find-ClientInSnapshot $snapshot $name
            if ($item) {
                Click-ListItem $ws $snapshot $item
                Write-Host " OK" -ForegroundColor Green
            } else {
                Write-Host " NOT FOUND in snapshot" -ForegroundColor Red
            }
            Start-Sleep -Seconds 3
        } else {
            Write-Host "  [NOT FOUND] $name" -ForegroundColor Red
        }
    }
}

# Cleanup
if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", [System.Threading.CancellationToken]::None).Wait()
}
$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
