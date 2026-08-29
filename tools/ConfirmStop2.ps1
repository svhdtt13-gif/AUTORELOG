#ConfirmStop2.ps1 - Click correct "Có" button
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

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }

# Caps + launch
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
Start-Sleep -Milliseconds 300

# list_menu r=5 to trigger stop confirmation
Write-Host "Opening stop dialog for row 5 (khoqua10)..." -ForegroundColor Yellow
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":5}'
Start-Sleep -Seconds 2

# Drain messages, find msgbox
$buf = New-Object byte[] 1048576
$foundDialog = $false
$timeout = [DateTime]::UtcNow.AddSeconds(3)
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") {
                Write-Host "snapshot gen=$($p.gen) sepoch=$($p.sepoch)" -ForegroundColor Green
                # Find msgbox buttons
                function Find-MsgBox($node) {
                    if ($node.popup -eq $true -and $node.kind -eq "msgbox") {
                        Write-Host "DIALOG: $($node.key)" -ForegroundColor Green
                        if ($node.children) {
                            foreach ($c in $node.children) {
                                $txt = if ($c.text) { $c.text } else { "" }
                                $kind = $c.kind
                                Write-Host "  [$kind] '$txt' key=$($c.key)" -ForegroundColor Cyan
                            }
                        }
                        return $true
                    }
                    if ($node.children) { foreach ($c in $node.children) { if (Find-MsgBox $c) { return $true } } }
                    return $false
                }
                Find-MsgBox $p.b | Out-Null
                $foundDialog = $true
            }
            $ms.Dispose()
        } else { $ms.Dispose(); break }
    } catch { break }
}

if (-not $foundDialog) { Write-Host "No dialog!" -ForegroundColor Red; $ws.Dispose(); exit 1 }

# Click "Có" button - key popup/0/6#0
Write-Host "`nClicking 'Có' button (popup/0/6#0)..." -ForegroundColor Yellow

# Try 3 formats: k+click, key+click, key+menu_click
$buttons = @(
    @{ t="act"; k="popup/0/6#0"; op="click" },
    @{ t="act"; key="popup/0/6#0"; op="click" },
    @{ t="act"; k="popup/0/6#0"; op="toggle" }
)

foreach ($btn in $buttons) {
    if ($ws.State -ne "Open") { break }
    $msg = $btn | ConvertTo-Json -Compress
    Write-Host "`nSend: $msg" -ForegroundColor Yellow
    Send- $msg
    Start-Sleep -Seconds 1
    
    # Quick check state
    $timeout2 = [DateTime]::UtcNow.AddSeconds(2)
    while ([DateTime]::UtcNow -lt $timeout2 -and $ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $ws.State -eq "Open") {
                $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(500)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) {
                $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($p.t -eq "act_result") { Write-Host "  RESULT: ok=$($p.ok) reason=$($p.reason)" -ForegroundColor $(if ($p.ok) { "Green" } else { "Red" }) }
                elseif ($p.t -eq "snapshot") { Write-Host "  snapshot" -ForegroundColor Green }
                else { Write-Host "  $($p.t)" -ForegroundColor DarkGray }
                $ms.Dispose()
            } else { $ms.Dispose(); break }
        } catch { break }
    }
    Write-Host "  state=$($ws.State)" -ForegroundColor $(if ($ws.State -eq "Open") { "Green" } else { "Red" })
}

$ws.Dispose()
