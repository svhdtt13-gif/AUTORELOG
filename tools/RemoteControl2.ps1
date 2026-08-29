#RemoteControl2.ps1 - Open/close clients by name
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
    $caps = @{ t = "caps"; proto = 3; gen = 1; actres = 1 } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($caps)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    return $ws
}

function Get-Data($ws) {
    $ct = [System.Threading.CancellationToken]::None
    $receiveBuf = New-Object byte[] 131072
    $snapshot = $null; $scrList = $null
    $timeout = [DateTime]::UtcNow.AddSeconds(5)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        try {
            $result = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$receiveBuf)), $ct)
            if ($result.AsyncWaitHandle.WaitOne(1000) -and $result.Result.Count -gt 0) {
                $msg = [System.Text.Encoding]::UTF8.GetString($receiveBuf, 0, $result.Result.Count)
                try { $p = $msg | ConvertFrom-Json; if ($p.t -eq "snapshot") { $snapshot = $p }; if ($p.t -eq "scr_list_res") { $scrList = $p } } catch {}
            }
        } catch { break }
    }
    return @{ snapshot = $snapshot; scrList = $scrList }
}

function Find-Client($scrList, $name) {
    if (-not $scrList -or -not $scrList.instances) { return $null }
    foreach ($inst in $scrList.instances) {
        $n = $inst.name.Trim()
        if ($n -like "*$name*" -or $name -like "*$n*") {
            return @{ idx = $inst.idx; state = $inst.state; name = $n; id = $inst.id }
        }
    }
    return $null
}

function Find-ItemInSnapshot($snapshot, $name) {
    if (-not $snapshot -or -not $snapshot.b) { return $null }
    function Search($children) {
        foreach ($c in $children) {
            if ($c.kind -eq "list" -and $c.items) {
                foreach ($item in $c.items) {
                    if ($item.c -and $item.c.Count -gt 1) {
                        if ($item.c[1].Trim() -like "*$name*" -or $name -like "*$($item.c[1].Trim())*") {
                            return $item
                        }
                    }
                }
            }
            if ($c.children) { $r = Search $c.children; if ($r) { return $r } }
        }
        return $null
    }
    return Search $snapshot.b.children
}

function Click($ws, $x, $y, $lgen) {
    $ct = [System.Threading.CancellationToken]::None
    $d = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $true; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($d)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    $u = @{ t = "scr_input"; idx = 0; dt = "mouse"; x = [int]$x; y = [int]$y; btn = "left"; down = $false; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($u)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

function Click-XButton($ws, $emuIdx, $lgen) {
    # Click X button on emulator title bar via its screen index
    # X button is at top-right of window: approx (width-25, 15)
    # Remote screen is typically 800x600 or similar
    $ct = [System.Threading.CancellationToken]::None
    $x = 775  # right side
    $y = 15   # top
    
    $d = @{ t = "scr_input"; idx = $emuIdx; dt = "mouse"; x = $x; y = $y; btn = "left"; down = $true; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($d)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
    Start-Sleep -Milliseconds 50
    $u = @{ t = "scr_input"; idx = $emuIdx; dt = "mouse"; x = $x; y = $y; btn = "left"; down = $false; lgen = $lgen } | ConvertTo-Json -Compress
    $buf = [System.Text.Encoding]::UTF8.GetBytes($u)
    $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$buf)), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $ct).Wait()
}

# === MAIN ===
Write-Host "Connecting..." -ForegroundColor Cyan
$ws = Connect-Remote
$data = Get-Data $ws
$snapshot = $data.snapshot
$scrList = $data.scrList
$lgen = if ($snapshot) { $snapshot.gen } else { 1 }
Write-Host "Connected! gen=$lgen" -ForegroundColor Green

if ($Action -eq "list") {
    Write-Host "`n=== ALL CLIENTS ===" -ForegroundColor Cyan
    foreach ($inst in ($scrList.instances | Sort-Object idx)) {
        $st = if ($inst.state -eq "running") { "[ON] " } else { "[OFF]" }
        $cl = if ($inst.state -eq "running") { "Green" } else { "Red" }
        Write-Host ("  {0} idx={1,-2} {2,-15} {3}" -f $st, $inst.idx, $inst.name.Trim(), ($inst.id -split ":")[1]) -ForegroundColor $cl
    }
    $on = ($scrList.instances | Where-Object { $_.state -eq "running" }).Count
    $off = ($scrList.instances | Where-Object { $_.state -ne "running" }).Count
    Write-Host "`nON: $on | OFF: $off | Total: $($scrList.instances.Count)" -ForegroundColor White
}

if ($Close.Count -gt 0) {
    Write-Host "`n=== CLOSING (click X button) ===" -ForegroundColor Yellow
    foreach ($name in $Close) {
        $info = Find-Client $scrList $name
        if ($info -and $info.state -eq "running") {
            Write-Host "  Closing $name (emu idx=$($info.idx))..." -NoNewline -ForegroundColor Gray
            Click-XButton $ws $info.idx $lgen
            Write-Host " OK" -ForegroundColor Green
            Start-Sleep -Seconds 3
        } elseif ($info) {
            Write-Host "  [SKIP] $name already offline" -ForegroundColor Yellow
        } else {
            Write-Host "  [NOT FOUND] $name" -ForegroundColor Red
        }
    }
}

if ($Open.Count -gt 0) {
    Write-Host "`n=== OPENING (click checkbox) ===" -ForegroundColor Yellow
    if ($Close.Count -gt 0) {
        Start-Sleep -Seconds 3
        $data = Get-Data $ws
        $snapshot = $data.snapshot
        $scrList = $data.scrList
        $lgen = if ($snapshot) { $snapshot.gen } else { $lgen }
    }
    
    foreach ($name in $Open) {
        $info = Find-Client $scrList $name
        if ($info -and $info.state -eq "running") {
            Write-Host "  [SKIP] $name already running" -ForegroundColor Yellow
        } elseif ($info) {
            Write-Host "  Opening $name (idx=$($info.idx))..." -NoNewline -ForegroundColor Gray
            $item = Find-ItemInSnapshot $snapshot $name
            if ($item -and $item.r) {
                $r = $item.r
                $clickX = [int]($r[0] + 12)
                $clickY = [int]($r[1] + ($r[3] / 2))
                Click $ws $clickX $clickY $lgen
                Write-Host " OK (click at $clickX,$clickY)" -ForegroundColor Green
            } else {
                Write-Host " NOT FOUND in snapshot" -ForegroundColor Red
            }
            Start-Sleep -Seconds 3
        } else {
            Write-Host "  [NOT FOUND] $name" -ForegroundColor Red
        }
    }
}

if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
    $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", [System.Threading.CancellationToken]::None).Wait()
}
$ws.Dispose()
Write-Host "`nDone!" -ForegroundColor Cyan
