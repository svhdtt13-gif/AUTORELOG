param(
  [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
  [string]$ClientId   = '',
  [int]$Idx           = -1,
  [string]$Key        = '',
  [string]$OutPath    = (Join-Path $PSScriptRoot 'b2_result.json')
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AUTORELOG.Ws.psm1') -Force

if (-not (Test-Path (Join-Path $PSScriptRoot 'config.json'))) { Write-Error "Thiếu config.json. Copy config.json.sample, điền token."; exit 2 }

$cfg = Get-AutorelogConfig $ConfigPath
$ws  = [System.Net.WebSockets.ClientWebSocket]::new()
if ($cfg.headers) { foreach ($k in $cfg.headers.PSObject.Properties.Name) { $ws.Options.SetRequestHeader($k, $cfg.headers.$k) } }
$cts = [System.Threading.CancellationTokenSource]::new()
$ws.ConnectAsync([System.Uri]::new($cfg.wsUrl), $cts.Token).GetAwaiter().GetResult()
if ($cfg.authMessage)     { Send-WsText $ws $cts $cfg.authMessage }
if ($cfg.subscribeMessage) { Send-WsText $ws $cts $cfg.subscribeMessage }

function Recv($ms) {
  $buf = [byte[]]::new(65536)
  $seg = [ArraySegment[byte]]::new($buf)
  $t = $ws.ReceiveAsync($seg, $cts.Token)
  if (-not $t.Wait($ms)) { return $null }
  $res = $t.Result
  if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
  return [System.Text.Encoding]::UTF8.GetString($buf, 0, $res.Count)
}

# chờ scr_list_res đầu tiên
$snap = $null
for ($i = 0; $i -lt 60; $i++) {
  $m = Recv 2000
  if ($m -and $m -match '"scr_list_res"') { $snap = $m; break }
}
if (-not $snap) { Write-Error 'Không nhận được scr_list_res. Kiểm tra wsUrl/auth trong config.json.'; exit 1 }

$insts = Get-ScrInstances $snap
$target = if ($ClientId) { $insts | Where-Object { $_.clientId -eq $ClientId } | Select-Object -First 1 }
          elseif ($Idx -ge 0) { $insts | Where-Object { [int]$_.idx -eq $Idx } | Select-Object -First 1 }
          else { $insts | Select-Object -First 1 }
if (-not $target) { Write-Error 'Không tìm thấy client mục tiêu.'; exit 1 }

$stateBefore = $target.state
$idx = [int]$target.idx

# suy key: ưu tiên field key có sẵn, kế đến -Key, kế đến giả thuyết root/<sess>#idx
$key = if ($target.key) { $target.key }
       elseif ($Key) { $Key }
       else {
         $sess = '1000'
         $sib = @($insts | Where-Object { $_.key -and $_.key -match 'root/(\d+)#' }) | Select-Object -First 1
         if ($sib) { $sess = $Matches[1] }
         "root/$sess#$idx"
       }
$epoch = if ($target.epoch -ne $null) { $target.epoch } else { 0 }
$reqId = 'cap:1'

Write-Host "Target: $($target.clientId) idx=$idx state=$stateBefore"
Write-Host "Sending row_toggle key=$key epoch=$epoch id=$reqId"
$act = [pscustomobject]@{ t='act'; key=$key; op='row_toggle'; r=$idx; id=$reqId; epoch=$epoch } | ConvertTo-Json -Compress
Send-WsText $ws $cts $act

$ack = $null; $stateAfter = $null
for ($i = 0; $i -lt 60; $i++) {
  $m = Recv 2000
  if (-not $m) { continue }
  if ($m -match '"act_result"' -and $m -match [regex]::Escape($reqId)) { $ack = $m | ConvertFrom-Json }
  if ($m -match '"scr_list_res"') {
    $post = Get-ScrInstances $m | Where-Object { $_.clientId -eq $target.clientId } | Select-Object -First 1
    if ($post) { $stateAfter = $post.state; break }
  }
}

$correlated = ($null -ne $stateAfter) -and ($stateAfter -ne $stateBefore)
$result = [ordered]@{
  ts           = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
  clientId     = $target.clientId
  idx          = $idx
  key          = $key
  epoch        = $epoch
  stateBefore  = $stateBefore
  actResult    = $ack
  stateAfter   = $stateAfter
  correlation  = if ($correlated) { 'PASS' } else { 'UNCONFIRMED' }
  note         = 'row_toggle đổi state qua runtime snapshot. Nếu stateAfter null -> chỉ có ACK, chưa transition (ACK_ONLY).'
}
$result | ConvertTo-Json -Depth 6 | Set-Content -Path $OutPath -Encoding UTF8
Write-Host "`nact_result: $(if($ack){$ack.ok}else{'none'})  stateBefore=$stateBefore -> stateAfter=$stateAfter"
Write-Host "Correlation: $($result.correlation)"
Write-Host "Detail -> $OutPath"
try { $ws.Dispose() } catch {}
