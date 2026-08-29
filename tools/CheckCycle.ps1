#CheckCycle.ps1 - verify the full daily cycle ran: all 4 slots done, group running, fixed alive, daemon alive
# Writes a timestamped report into cache/cycle_check_<date>.txt (view later while debugging)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = "C:\Users\ADMIN\Documents\ai tool\tools"
$rows = New-Object System.Collections.ArrayList
function Add-R($k, $v, $ok) { [void]$rows.Add([PSCustomObject]@{ C = $k; V = $v; OK = $ok }) }

# 1) state file
$statePath = "$dir\cache\cycle_state.json"
if (Test-Path $statePath) {
    $st = Get-Content $statePath -Raw | ConvertFrom-Json
    Add-R "state.today" $st.today $true
    $dp = @()
    if ($st.done -is [System.Management.Automation.PSCustomObject]) { foreach ($p in $st.done.PSObject.Properties) { $dp += "$($p.Name)=$($p.Value)" } } else { foreach ($k in $st.done.Keys) { $dp += "$k=$($st.done[$k])" } }
    $dp | ForEach-Object { Add-R "done" $_ $true }
} else { Add-R "state file" "MISSING" $false }

# 2) log: extract SLOT ... DONE lines for today
$log = "$dir\cache\cycle.log"
if (Test-Path $log) {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $doneSlots = @(Get-Content $log | Where-Object { $_ -match "\[$today" -and $_ -match 'SLOT (.+?) DONE' } | ForEach-Object { ($_ -replace '^.*SLOT (.+?) DONE.*$', '$1') } | Sort-Object -Unique)
    Add-R "slots DONE today ($($doneSlots.Count)/4)" ($doneSlots -join ', ') ($doneSlots.Count -ge 4)
}

# 3) daemon alive?
$daemon = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -match 'AutoCycle.ps1' -and $_.CommandLine -match '-Background' })
Add-R "daemon -Background alive" ($daemon.Count) ($daemon.Count -ge 1)

# 4) live probe: checked rows + qnyh count + scr_list states
$data = Get-Content "$dir\remote_session.json" | ConvertFrom-Json
$token = $data.session; $appRoom = "e1c51deba15917ba"
$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.Options.SetRequestHeader("Authorization", "Bearer $token"); $ws.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
$uri = New-Object System.Uri("wss://remote.360auto.net/ws/viewer?room=$appRoom&session=$token")
$ct = [System.Threading.CancellationToken]::None; $ws.ConnectAsync($uri, $ct).Wait()
function Send-($m) { $b = [System.Text.Encoding]::UTF8.GetBytes($m); $ws.SendAsync((New-Object System.ArraySegment[byte] -ArgumentList @(,$b)), "Text", $true, $ct).Wait() }
$buf = New-Object byte[] 2097152
Send- '{"t":"caps","proto":3,"gen":1,"actres":1}'; Start-Sleep -Milliseconds 300
Send- '{"t":"launch","product_id":73}'
function DrainQS($ws, [int]$secs) {
    $timeout = [DateTime]::UtcNow.AddSeconds($secs)
    while ([DateTime]::UtcNow -lt $timeout -and $ws.State -eq "Open") {
        $ms = New-Object System.IO.MemoryStream; $more = $true
        while ($more -and $ws.State -eq "Open") {
            $r = $ws.ReceiveAsync((New-Object System.ArraySegment[byte] -ArgumentList (,$buf)), $ct)
            if (-not $r.AsyncWaitHandle.WaitOne(400)) { $more = $false } else { $ms.Write($buf,0,$r.Result.Count); $more = -not $r.Result.EndOfMessage }
        }
        if ($ms.Length -gt 0) { $p = [System.Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json -ErrorAction SilentlyContinue; if ($p.t -eq "snapshot") { return $p } }
        $ms.Dispose()
    }
    return $null
}
$snap = DrainQS $ws 12
if (-not $snap) { Add-R "snapshot" "FAILED" $false; $checked = @{} } else {
    $checked = @{}
    foreach ($n in $snap.b.children) { if ($n.key -eq "root/1000#0") { foreach ($rw in $n.rows) { $checked[[int]$rw.r] = [int]$rw.checked } } }
    $all24 = ($checked.GetEnumerator() | Where-Object { $_.Key -ge 0 -and $_.Key -le 4 } | Measure-Object -Property Value -Sum).Sum
    Add-R "fixed rows r0-4 checked sum" "$all24/5 (expect 5)" ($all24 -eq 5)
    $onTotal = @($checked.GetEnumerator() | Where-Object { $_.Value -eq 1 }).Count
    Add-R "rows checked=1 (total)" $onTotal ($onTotal -ge 10)
    $grp5 = @($checked.GetEnumerator() | Where-Object { $_.Key -in @(10,11,12,13,14) -and $_.Value -eq 1 }).Count
    Add-R "19:45 group r10-14 checked" "$grp5/5" ($grp5 -eq 5)
}
$q = (Get-Process qnyh -ErrorAction SilentlyContinue | Measure-Object).Count
Add-R "qnyh.exe procs" $q ($q -ge 6)
$ws.Dispose()

# 5) report to file
$rep = "$dir\cache\cycle_check_$(Get-Date -Format 'yyyy-MM-dd').txt"
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("=== cycle check $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===")
foreach ($r in $rows) { [void]$sb.AppendLine(("{0,-40} {1,-50} {2}" -f $r.C, $r.V, $(if ($r.OK) { 'OK' } else { 'FAIL' }))) }
Set-Content $rep $sb.ToString() -Encoding UTF8
$rows | Format-Table -AutoSize | Out-String | Write-Host
Write-Host "report -> $rep"