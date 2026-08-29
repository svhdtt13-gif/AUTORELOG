#TestListMenu9.ps1 - Capture ALL messages after list_menu r=9 (deltas included)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"
$ct = [System.Threading.CancellationToken]::None
$buf = New-Object byte[] 1048576

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
function Drain([int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $json = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
                $p = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p) {
                    Write-Host "`n--- $($p.t) ---" -ForegroundColor Cyan
                    Write-Host "  keys: $(($p.PSObject.Properties.Name) -join ', ')" -ForegroundColor DarkGray
                    if ($p.t -eq "snapshot" -or $p.t -eq "delta") {
                        if ($p.b) {
                            foreach ($n in $p.b.children) {
                                $txt = ($n.text -replace '[^\x20-\x7E]','')
                                Write-Host "  child key=$($n.key) kind=$($n.kind) en=$($n.en) title='$txt'" -ForegroundColor Gray
                            }
                        }
                        if ($p.patch) { Write-Host "  patch: $($p.patch | ConvertTo-Json -Compress -Depth 6)" -ForegroundColor DarkGray }
                    }
                    elseif ($p.t -eq "act_result") { Write-Host "  ok=$($p.ok) reason=$($p.reason)" -ForegroundColor Yellow }
                    elseif ($p.t -eq "scr_status") { Write-Host "  [scr_status]" -ForegroundColor DarkGray }
                } else { Write-Host "  [raw] $json" -ForegroundColor Yellow }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { Write-Host "  [recv err] $($_.Exception.InnerException.Message)" -ForegroundColor Red; break }
    }
    Write-Host "  state=$($ws.State)" -ForegroundColor $(if($ws.State -eq "Open"){"Green"}else{"Red"})
}

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Write-Host "`n=== Initial (drain 4s) ===" -ForegroundColor Magenta
Drain 4
Write-Host "`n=== SEND list_menu r=9 ===" -ForegroundColor Magenta
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
Write-Host "sent, draining 6s..."
Drain 6
$ws.Dispose()