#OpenClient14_v2.ps1 - Simple format that worked before
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$sessionData = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $sessionData.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# list_menu r=0 for client_14
Write-Host "list_menu r=0 (client_14)..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":0}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                Write-Host "snapshot gen=$($p.gen)" -ForegroundColor Green
                function Show-Popup($node) {
                    if ($node.popup -eq $true) {
                        Write-Host "POPUP kind=$($node.kind) key=$($node.key)" -ForegroundColor Green
                        if ($node.items) {
                            $i = 0; foreach ($item in $node.items) {
                                $t = if ($item.t) { $item.t } else { "?" }; $dis = if ($item.dis) { " [DIS]" } else { "" }
                                Write-Host "  [$i] '$t'$dis" -ForegroundColor Cyan; $i++
                            }
                        }
                        if ($node.children) { foreach ($c in $node.children) {
                            $txt = if ($c.text) { $c.text } else { "" }
                            Write-Host "  $($c.kind) '$txt' key=$($c.key)" -ForegroundColor Cyan
                        }}
                    }
                    if ($node.children) { foreach ($c in $node.children) { Show-Popup $c } }
                }
                Show-Popup $p.b
            }
            elseif ($p.t -eq "act_result") { Write-Host "act_result ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Cyan }
            elseif ($p.t -eq "delta") { Write-Host "delta" -ForegroundColor DarkGray }
            elseif ($p.t -eq "scr_list_res") { Write-Host "scr_list_res" -ForegroundColor DarkGray }
            elseif ($p.t -eq "_presence" -or $p.t -eq "_roster") { Write-Host $p.t -ForegroundColor DarkGray }
            else { Write-Host "$($p.t)" -ForegroundColor Gray }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

Write-Host "state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
$ws.Dispose()
