#DumpRowStructure.ps1 - full JSON of running row 9 (act/cells/checked)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$data = Get-Content "C:\Users\ADMIN\Documents\ai tool\tools\remote_session.json" | ConvertFrom-Json
$token = $data.session
$appRoom = "e1c51deba15917ba"

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token")
$ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None
$ws.ConnectAsync($uri, $ct).Wait()
Write-Host "Connected: $($ws.State)" -ForegroundColor Green

function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 1048576

Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'
Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'

$timeout = [DateTime]::UtcNow.AddSeconds(8)
$snap = $null
while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
    try {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if ($r.AsyncWaitHandle.WaitOne(1000)) { $ms.Write($buf, 0, $r.Result.Count); $more = -not $r.Result.EndOfMessage } else { $more = $false }
        }
        if ($ms.Length -gt 0) {
            $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($p.t -eq "snapshot") { $snap = $p }
        } else { $ms.Dispose(); break }
        $ms.Dispose()
    } catch { break }
}

foreach ($n in $snap.b.children) {
    if ($n.key -eq "root/1000#0") {
        $rows = $n.rows
        Write-Host "=== LIST node full keys: $(($n.PSObject.Properties.Name) -join ', ')" -ForegroundColor Cyan
        Write-Host "=== ROW 9 FULL JSON ===" -ForegroundColor Cyan
        $row9 = $rows | Where-Object { $_.r -eq 9 }
        $row9 | ConvertTo-Json -Depth 10
        Write-Host "`n=== ROW 0 FULL JSON (offline example) ===" -ForegroundColor Cyan
        $rows | Where-Object { $_.r -eq 0 } | ConvertTo-Json -Depth 10
        Write-Host "`n=== ALL running rows (r, chk, checked, act, c) ===" -ForegroundColor Cyan
        foreach ($row in $rows) {
            $acts = ""
            if ($row.act) { $acts = ($row.act | ForEach-Object { "c=$($_.c):$($_.tip -replace '[^\x20-\x7E]','.')" }) -join ' | ' }
            Write-Host "  r=$($row.r) chk=$($row.chk) checked=$($row.checked) act='$acts'" -ForegroundColor DarkGray
        }
    }
}
$snap | ConvertTo-Json -Depth 12 | Out-File "C:\Users\ADMIN\Documents\ai tool\tools\snapshot_full_detail.json" -Encoding UTF8
Write-Host "`nSaved snapshot_full_detail.json ($((Get-Item 'C:\Users\ADMIN\Documents\ai tool\tools\snapshot_full_detail.json').Length) bytes)" -ForegroundColor DarkGray
$ws.Dispose()