#TestClose.ps1 - OPEN flow: list_menu r=9 -> click "Có" -> verify row 9 becomes 0
# Then close flow test on row 9 (client_7 khoqua09)
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
function Receive-All([int]$secs) {
    $buf = $script:buf
    $timeout = [DateTime]::UtcNow.AddSeconds($secs); $msgs = @()
    while ([DateTime]::UtcNow -lt $timeout -and $script:ws.State -eq "Open") {
        try {
            $ms = New-Object System.IO.MemoryStream; $more = $true
            while ($more -and $script:ws.State -eq "Open") {
                $r = $script:ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
                if ($r.AsyncWaitHandle.WaitOne(800)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
            }
            if ($ms.Length -gt 0) { $msgs += [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) } else { $ms.Dispose(); break }
            $ms.Dispose()
        } catch { break }
    }
    return $msgs
}
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$epoch = 0
foreach ($raw in (Receive-All 6)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") { $epoch = $p.sepoch; Write-Host "snapshot sepoch=$epoch" -ForegroundColor DarkGray }
}
Write-Host "State: $($ws.State)" -ForegroundColor Cyan

# Step 1: open context menu on row 9
Write-Host "`n=== STEP 1: list_menu r=9 ===" -ForegroundColor Green
Send- '{"t":"act","k":"root/1000#0","op":"list_menu","r":9}'
foreach ($raw in (Receive-All 4)) {
    $p = $raw | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($p.t -eq "snapshot") {
        # find popup keys
        foreach ($n in $p.b.children) {
            $txt = ($n.text -replace '[^\x20-\x7E]','')
            if ($n.kind -in @('dialog','contextmenu') -or $n.key -match 'popup|menu') {
                Write-Host "  node key=$($n.key) kind=$($n.kind) title='$txt'" -ForegroundColor Cyan
                if ($n.children) { foreach ($c in $n.children) { Write-Host "    child key=$($c.key) text='$(($c.text -replace '[^\x20-\x7E]',''))'" -ForegroundColor DarkGray } }
            }
        }
    }
}
Write-Host "State after list_menu: $($ws.State)" -ForegroundColor Cyan

$ws.Dispose()